import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/database_helper.dart';
import '../models/access_log_entry.dart';
import 'mustache_renderer.dart';
import 'mustache_template_service.dart';

class ProvisioningServer {
  static final ProvisioningServer instance = ProvisioningServer._();
  ProvisioningServer._();
  static HttpServer? _server;
  static String? _serverUrl;

  // --- Access Log State ---
  // The broadcast StreamController is intentionally kept open for the lifetime
  // of the app so that UI listeners survive server restarts without needing to
  // re-subscribe.  The log list and maps are cleared in stop() to give each
  // server session a clean slate.
  static final _logController = StreamController<AccessLogEntry>.broadcast();
  static final List<AccessLogEntry> _accessLog = [];
  static final Map<String, Set<String>> _deviceAccessMap = {};
  /// IP → MAC lookup built as devices fetch their named config files.
  static final Map<String, String> _ipMacMap = {};

  static Stream<AccessLogEntry> get accessLogStream => _logController.stream;
  static List<AccessLogEntry> get accessLog => List.unmodifiable(_accessLog);
  static Map<String, Set<String>> get deviceAccessMap =>
      Map.unmodifiable(_deviceAccessMap);

  static String? get serverUrl => _serverUrl;

  // ---------------------------------------------------------------------------
  // Classify the requested path into a resource type string.
  // ---------------------------------------------------------------------------
  static String _classifyResource(String path) {
    if (path.startsWith('/media/original/')) return 'original_media';
    if (path.startsWith('/media/')) return 'wallpaper';
    if (path.startsWith('/ringtones/')) return 'ringtone';
    if (path.startsWith('/phonebook/')) return 'phonebook';
    if (path.startsWith('/templates/')) return 'template';
    return 'config';
  }

  // ---------------------------------------------------------------------------
  // Extract a 12-hex-char MAC from a filename in the path, e.g. /AABBCCDDEEFF.cfg
  // ---------------------------------------------------------------------------
  static String? _extractMacFromPath(String path) {
    final match =
        RegExp(r'([0-9A-Fa-f]{12})\.(cfg|xml)$').firstMatch(path);
    return match?.group(1)?.toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // Try to extract MAC address from User-Agent header.
  // Many Yealink/Poly/Cisco phones include their MAC in UA strings, e.g.:
  //   Yealink SIP-T54W 96.86.0.100 AA:BB:CC:DD:EE:FF
  // ---------------------------------------------------------------------------
  static String? _extractMacFromUserAgent(String? ua) {
    if (ua == null) return null;
    // Colon-separated (AA:BB:CC:DD:EE:FF)
    final colonMatch =
        RegExp(r'([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})').firstMatch(ua);
    if (colonMatch != null) {
      return colonMatch.group(1)!.replaceAll(':', '').toUpperCase();
    }
    // Bare 12-hex (AABBCCDDEEFF)
    final bareMatch =
        RegExp(r'\b([0-9A-Fa-f]{12})\b').firstMatch(ua);
    return bareMatch?.group(1)?.toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // Custom access-logging middleware.
  // ---------------------------------------------------------------------------
  static Middleware _accessLogMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final response = await inner(request);

        // --- Resolve client IP ---
        final connInfo = request.context['shelf.io.connection_info'];
        final String clientIp = (connInfo is HttpConnectionInfo)
            ? connInfo.remoteAddress.address
            : 'unknown';

        final path = '/${request.url.path}';
        final resourceType = _classifyResource(path);

        // --- Resolve MAC ---
        String? mac = _extractMacFromPath(path);
        if (mac != null) {
          // Record the IP → MAC mapping for subsequent requests from same device
          _ipMacMap[clientIp] = mac;
        } else {
          // Fallback: IP map, then User-Agent
          mac = _ipMacMap[clientIp] ??
              _extractMacFromUserAgent(request.headers['user-agent']);
        }

        // --- Look up device label ---
        String? deviceLabel;
        if (mac != null) {
          try {
            final device = await DatabaseHelper.instance.getDeviceByMac(mac);
            if (device != null) {
              deviceLabel = 'Ext ${device.extension} - ${device.label}';
            }
          } catch (_) {
            // Non-fatal: label lookup failure should not break request handling
          }

          // Track resource types accessed per MAC
          _deviceAccessMap.putIfAbsent(mac, () => <String>{}).add(resourceType);
        }

        final entry = AccessLogEntry(
          clientIp: clientIp,
          requestedPath: path,
          resolvedMac: mac,
          deviceLabel: deviceLabel,
          resourceType: resourceType,
          statusCode: response.statusCode,
          timestamp: DateTime.now(),
        );

        if (_accessLog.length >= 2000) {
          _accessLog.removeRange(0, _accessLog.length - 1999);
        }
        _accessLog.add(entry);
        if (!_logController.isClosed) {
          _logController.add(entry);
        }

        return response;
      };
    };
  }

  static Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final response = await inner(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
        });
      };
    };
  }

  Future<String> start([int port = 8080]) async {
    await stop();

    final router = Router();
    final info = NetworkInfo();
    String? myIp = await info.getWifiIP();

    // Native fallback: enumerate network interfaces for a valid IPv4 address
    if (myIp == null) {
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);

        // Sort interfaces so physical Wi-Fi/Ethernet adapters come before virtual/VPN ones
        final sortedInterfaces = interfaces.toList()..sort((a, b) {
          final aName = a.name.toLowerCase();
          final bName = b.name.toLowerCase();
          final aIsPhysical = aName.startsWith('wlan') || aName.startsWith('eth') || aName.startsWith('en');
          final bIsPhysical = bName.startsWith('wlan') || bName.startsWith('eth') || bName.startsWith('en');
          if (aIsPhysical && !bIsPhysical) return -1;
          if (!aIsPhysical && bIsPhysical) return 1;
          return aName.compareTo(bName);
        });

        for (final iface in sortedInterfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              myIp = addr.address;
              break;
            }
          }
          if (myIp != null) break;
        }
      } catch (_) {
        // Ignore errors from native interface lookup
      }
    }

    myIp ??= '0.0.0.0';

    // --- TEMPLATE HANDLER ---
    router.get('/templates/<filename>', (Request request, String filename) async {
      final templateKey = filename.endsWith('.mustache')
          ? filename.substring(0, filename.length - 9)
          : filename;

      try {
        final content = await MustacheTemplateService.instance.loadTemplate(templateKey);
        final contentType = MustacheTemplateService.instance.getContentType(templateKey);

        return Response.ok(content, headers: {'Content-Type': contentType});
      } catch (e) {
        return Response.notFound('Template not found: $e');
      }
    });

    // --- MEDIA HANDLER (original files) ---
    router.get('/media/original/<file>', (Request request, String file) async {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = p.join(directory.path, 'media', 'original', file);
      final imageFile = File(filePath);

      if (await imageFile.exists()) {
        final bytes = await imageFile.readAsBytes();
        final ext = p.extension(file).toLowerCase();
        final mime = ext == '.png' ? 'image/png' : 'image/jpeg';
        return Response.ok(bytes, headers: {
          'Content-Type': mime,
        });
      }
      return Response.notFound('Original media file not found');
    });

    // --- MEDIA HANDLER ---
    router.get('/media/<file>', (Request request, String file) async {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = p.join(directory.path, 'media', file);
      final imageFile = File(filePath);

      if (await imageFile.exists()) {
        final bytes = await imageFile.readAsBytes();
        final mime = file.endsWith('.png') ? 'image/png' : 'image/jpeg';
        return Response.ok(bytes, headers: {
          'Content-Type': mime,
        });
      }
      return Response.notFound('Media file not found');
    });

    // --- RINGTONE HANDLER ---
    router.get('/ringtones/<file>', (Request request, String file) async {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = p.join(directory.path, 'ringtones', file);
      final audioFile = File(filePath);
      if (await audioFile.exists()) {
        final bytes = await audioFile.readAsBytes();
        return Response.ok(bytes, headers: {
          'Content-Type': 'audio/wav',
        });
      }
      return Response.notFound('Ringtone file not found');
    });

    // --- PHONEBOOK HANDLER ---
    router.get('/phonebook/<file>', (Request request, String file) async {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = p.join(directory.path, 'phonebook', file);
      final pbFile = File(filePath);
      if (await pbFile.exists()) {
        final content = await pbFile.readAsString();
        return Response.ok(content, headers: {
          'Content-Type': 'application/xml',
        });
      }
      return Response.notFound('Phonebook file not found');
    });

    // --- CONFIG HANDLER (dynamic generation with static fallback) ---
    router.get('/<filename>', (Request request, String filename) async {
      // --- Try dynamic config generation first ---
      final macMatch = RegExp(r'^([0-9a-fA-F]{12})\.(cfg|xml)$', caseSensitive: false).firstMatch(filename);

      if (macMatch != null) {
        final mac = macMatch.group(1)!.toUpperCase();
        final device = await DatabaseHelper.instance.getDeviceByMac(mac);

        if (device != null) {
          try {
            final templateKey = await MustacheRenderer.resolveTemplateKey(device.model);
            final ds = device.deviceSettings;

            // Resolve wallpaper URL
            String deviceWallpaperUrl = '';
            final deviceWallpaper = device.wallpaper;
            if (deviceWallpaper != null && deviceWallpaper.isNotEmpty) {
              if (deviceWallpaper.startsWith('LOCAL:') && _serverUrl != null) {
                final fname = deviceWallpaper.substring('LOCAL:'.length);
                deviceWallpaperUrl = '$_serverUrl/media/$fname';
              } else {
                deviceWallpaperUrl = deviceWallpaper;
              }
            }

            // Resolve ringtone URL
            String deviceRingtoneUrl = '';
            final deviceRingtone = ds?.ringtone;
            if (deviceRingtone != null && deviceRingtone.isNotEmpty) {
              if (deviceRingtone.startsWith('LOCAL:') && _serverUrl != null) {
                final fname = deviceRingtone.substring('LOCAL:'.length);
                deviceRingtoneUrl = '$_serverUrl/ringtones/$fname';
              } else {
                deviceRingtoneUrl = deviceRingtone;
              }
            }

            final variables = MustacheRenderer.buildVariables(
              macAddress: device.macAddress ?? mac,
              extension: device.extension,
              displayName: device.label,
              secret: device.secret,
              model: device.model,
              sipServer: ds?.sipServer ?? '',
              provisioningUrl: ds?.provisioningUrl ?? _serverUrl ?? '',
              sipPort: ds?.sipPort,
              transport: ds?.transport,
              regExpiry: ds?.regExpiry,
              outboundProxyHost: ds?.outboundProxyHost,
              outboundProxyPort: ds?.outboundProxyPort,
              backupServer: ds?.backupServer,
              backupPort: ds?.backupPort,
              voiceVlanId: ds?.voiceVlanId,
              dataVlanId: ds?.dataVlanId,
              wallpaperUrl: deviceWallpaperUrl,
              ringtoneUrl: deviceRingtoneUrl,
              ntpServer: ds?.ntpServer,
              timezone: ds?.timezone,
              adminPassword: ds?.adminPassword,
              voicemailNumber: ds?.voicemailNumber,
              screensaverTimeout: ds?.screensaverTimeout,
              webUiEnabled: ds?.webUiEnabled,
              cdpLldpEnabled: ds?.cdpLldpEnabled,
              autoAnswer: ds?.autoAnswer,
              autoAnswerMode: ds?.autoAnswerMode,
              dndDefault: ds?.dndDefault,
              callWaiting: ds?.callWaiting,
              cfwAlways: ds?.cfwAlways,
              cfwBusy: ds?.cfwBusy,
              cfwNoAnswer: ds?.cfwNoAnswer,
              syslogServer: ds?.syslogServer,
              dialPlan: ds?.dialPlan,
              dstEnable: ds?.dstEnable,
              debugLevel: ds?.debugLevel,
            );

            final content = await MustacheRenderer.render(templateKey, variables);
            final contentType = filename.toLowerCase().endsWith('.xml') ? 'application/xml' : 'text/plain';

            return Response.ok(content, headers: {'Content-Type': contentType});
          } catch (e) {
            // Dynamic generation failed, fall through to static file lookup
            print('Dynamic config generation failed for $mac: $e');
          }
        }
      }

      // --- Fallback to static generated files ---
      final directory = await getApplicationDocumentsDirectory();
      final configDir = Directory(p.join(directory.path, 'generated_configs'));

      if (!await configDir.exists()) {
        return Response.notFound('Config directory not found');
      }

      // Direct file lookups instead of blocking listSync()
      File match = File(p.join(configDir.path, filename));
      if (!await match.exists()) {
        match = File(p.join(configDir.path, filename.toLowerCase()));
      }
      if (!await match.exists()) {
        match = File(p.join(configDir.path, filename.toUpperCase()));
      }

      if (!await match.exists()) {
        return Response.notFound('Config file not found');
      }

      final content = await match.readAsString();
      final ext = p.extension(match.path).toLowerCase();
      final contentType = ext == '.xml' ? 'application/xml' : 'text/plain';
      return Response.ok(content, headers: {
        'Content-Type': contentType,
      });
    });

    try {
      final handler = const Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(_accessLogMiddleware())
          .addHandler(router.call);
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      _serverUrl = 'http://$myIp:$port';
      print('Server running: $_serverUrl');
      return _serverUrl!;
    } catch (e) {
      print("Error starting server: $e");
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _serverUrl = null;
      _accessLog.clear();
      _deviceAccessMap.clear();
      _ipMacMap.clear();
      print('Server stopped');
    }
  }
}
