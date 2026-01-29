import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';
import '../services/button_layout_service.dart';
import '../models/button_key.dart'; // For type reference

class ProvisioningServer {
  Future<String> start() async {
    final router = Router();

    final info = NetworkInfo();
    final String myIp = await info.getWifiIP() ?? '0.0.0.0';

    final prefs = await SharedPreferences.getInstance();
    final String? publicBgUrl = prefs.getString('public_wallpaper_url');
    final String finalWallpaperUrl = (publicBgUrl != null && publicBgUrl.isNotEmpty)
        ? publicBgUrl
        : "http://$myIp:8080/media/custom_bg.png";

    final String targetUrl = prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget;

    // Load all devices for efficient ext → label map (used in BLF label fallback)
    final List<Device> allDevices = await DatabaseHelper.instance.getAllDevices();
    final Map<String, String> extToLabel = {
      for (var d in allDevices) d.extension: d.label.isNotEmpty ? d.label : d.extension,
    };

    // Main route: Serve per-MAC config
    router.get('/<filename>', (Request request, String filename) async {
      // Normalize MAC
      String cleanMac = filename
          .toUpperCase()
          .replaceAll(RegExp(r'[:\.\-\s%3A]'), '')
          .replaceAll(RegExp(r'\.(cfg|xml|boot)$', caseSensitive: false), '');

      print('LOG: Request $filename → MAC $cleanMac');

      // Skip generics
      if (cleanMac.length < 12 || cleanMac == '000000000000' || cleanMac.startsWith('Y000')) {
        return Response.notFound('Generic request skipped');
      }

      final Device? device = await DatabaseHelper.instance.getDeviceByMac(cleanMac);
      if (device == null) {
        return Response.notFound('MAC $cleanMac not in list');
      }

      // Load template
      String rawTemplate = await DeviceTemplates.getTemplateForModel(device.model);
      String contentType = await DeviceTemplates.getContentType(device.model);

      // Core replacements
      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp)
          .replaceAll('{{wallpaper_url}}', finalWallpaperUrl)
          .replaceAll('{{target_url}}', targetUrl);

      // DSS/Programmable Keys Generation (Yealink-focused, inspired by standard provisioners)
      final List<ButtonKey> layout = await ButtonLayoutService.getLayoutForModel(device.model);
      String dssSection = '';

      for (final key in layout) {
        if (key.type == 'none' || key.value.isEmpty) continue;

        final String typeCode = switch (key.type) {
          'blf' => '16',       // BLF/Presence (most common for monitoring)
          'speeddial' => '2',  // Speed Dial
          'line' => '1',       // Additional Line/Key
          _ => '0',            // None/Disabled fallback
        };

        // Label priority: custom → monitored ext's device label → raw value
        final String effectiveLabel = key.label.isNotEmpty
            ? key.label
            : (extToLabel[key.value] ?? key.value);

        // Standard Yealink params (line=1 ties to primary account for calls)
        dssSection += '''
programmable_key.${key.id}.type = $typeCode
programmable_key.${key.id}.value = ${key.value}
programmable_key.${key.id}.label = $effectiveLabel
programmable_key.${key.id}.line = 1

''';
      }

      // Inject and trim
      config = config.replaceAll('{{dss_keys}}', dssSection.trim());

      return Response.ok(config, headers: {'Content-Type': contentType});
    });

    // Media stub (expand later for real image serving)
    router.get('/media/<file>', (Request request, String file) async {
      return Response.ok('Media file: $file (implement serving here)');
    });

    final server = await shelf_io.serve(router, '0.0.0.0', 8080);
    print('Server online: http://$myIp:8080');

    return 'http://$myIp:8080';
  }
}
