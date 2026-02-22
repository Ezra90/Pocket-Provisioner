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

        _accessLog.add(entry);
        if (!_logController.isClosed) {
          _logController.add(entry);
        }

        return response;
      };
    };
  }

  Future<String> start([int port = 8080]) async {
    await stop();

    final router = Router();
    final info = NetworkInfo();
    String? myIp = await info.getWifiIP();
    myIp ??= '0.0.0.0'; 

    // --- TEMPLATE HANDLER ---
    router.get('/templates/<filename>', (Request request, String filename) async {
      final directory = await getApplicationDocumentsDirectory();
      final templateDir = Directory(p.join(directory.path, 'custom_templates'));

      if (!await templateDir.exists()) {
        return Response.notFound('Templates directory not found');
      }

      // Look for exact .mustache file match
      final filePath = p.join(templateDir.path, filename);
      final file = File(filePath);

      // Also try appending .mustache if not already present
      final mustacheFile = filename.endsWith('.mustache')
          ? file
          : File('${filePath}.mustache');

      if (await mustacheFile.exists()) {
        final content = await mustacheFile.readAsString();
        return Response.ok(content, headers: {
          'Content-Type': 'text/plain',
          'Access-Control-Allow-Origin': '*',
        });
      }

      // Also check without .mustache extension if exact filename was given
      if (await file.exists()) {
        final content = await file.readAsString();
        return Response.ok(content, headers: {
          'Content-Type': 'text/plain',
          'Access-Control-Allow-Origin': '*',
        });
      }

      return Response.notFound('Template not found');
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
          'Access-Control-Allow-Origin': '*',
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
          'Access-Control-Allow-Origin': '*',
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
          'Access-Control-Allow-Origin': '*',
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
          'Access-Control-Allow-Origin': '*',
        });
      }
      return Response.notFound('Phonebook file not found');
    });

    // --- CONFIG HANDLER (static files) ---
    router.get('/<filename>', (Request request, String filename) async {
      final directory = await getApplicationDocumentsDirectory();
      final configDir = Directory(p.join(directory.path, 'generated_configs'));

      if (!await configDir.exists()) {
        return Response.notFound('Config directory not found');
      }

      // Case-insensitive file lookup (important for MAC address filenames)
      final files = configDir.listSync().whereType<File>();
      final matches = files.where(
        (f) => p.basename(f.path).toLowerCase() == filename.toLowerCase(),
      );
      final File? match = matches.isEmpty ? null : matches.first;

      if (match == null) {
        return Response.notFound('Config file not found');
      }

      final content = await match.readAsString();
      final ext = p.extension(match.path).toLowerCase();
      final contentType = ext == '.xml' ? 'application/xml' : 'text/plain';
      return Response.ok(content, headers: {
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*',
      });
    });

    try {
      final handler = const Pipeline()
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
