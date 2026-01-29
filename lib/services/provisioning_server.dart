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

    // Load all devices once for label lookup (ext → label map)
    final List<Device> allDevices = await DatabaseHelper.instance.getAllDevices();
    final Map<String, String> extToLabel = {
      for (var d in allDevices) d.extension: d.label,
    };

    // Main config route — FIXED: Use '/<filename>' to correctly capture MAC.cfg requests
    router.get('/<filename>', (Request request, String filename) async {
      // Clean and normalize the MAC from filename (e.g., 001565123456.cfg → 001565123456)
      String cleanMac = filename
          .toUpperCase()
          .replaceAll(RegExp(r'[:\.\-\s]'), '') // Remove common separators
          .replaceAll(RegExp(r'\.(cfg|xml|boot)$', caseSensitive: false), ''); // Remove extensions

      print('LOG: Requested filename: $filename → Parsed MAC: $cleanMac');

      // Skip generic/common config requests (Yealink common.cfg or 000000000000.cfg)
      if (cleanMac == '000000000000' || cleanMac.contains('Y0000000000') || cleanMac.isEmpty) {
        return Response.notFound('Generic config skipped');
      }

      // Fetch the specific device by MAC
      final Device? device = await DatabaseHelper.instance.getDeviceByMac(cleanMac);

      if (device == null) {
        return Response(404, body: 'MAC $cleanMac not found in provisioning list');
      }

      // Get template (DB-stored first, fallback to built-in)
      String rawTemplate = await DeviceTemplates.getTemplateForModel(device.model);

      // Determine content type (extend for Polycom later)
      String contentType = rawTemplate.contains('<') ? 'application/xml' : 'text/plain';

      // Basic replacements
      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp)
          .replaceAll('{{wallpaper_url}}', finalWallpaperUrl)
          .replaceAll('{{target_url}}', targetUrl);

      // NEW: Generate DSS/programmable keys section
      final List<ButtonKey> layout = await ButtonLayoutService.getLayoutForModel(device.model);
      String dssSection = '';

      for (final key in layout) {
        if (key.type == 'none' || key.value.isEmpty) continue;

        final String typeCode = switch (key.type) {
          'blf' => '16',        // BLF / Presence
          'speeddial' => '2',   // Speed Dial
          'line' => '1',        // Additional Line
          _ => '0',
        };

        // Use custom label if set, otherwise auto-lookup from another device's label (for BLF)
        final String effectiveLabel = key.label.isNotEmpty
            ? key.label
            : (extToLabel[key.value] ?? key.value);

        dssSection += '''
programmable_key.${key.id}.type = $typeCode
programmable_key.${key.id}.value = ${key.value}
programmable_key.${key.id}.label = $effectiveLabel
programmable_key.${key.id}.line = 1

''';
      }

      // Replace the placeholder (trim to avoid extra newlines)
      config = config.replaceAll('{{dss_keys}}', dssSection.trim());

      return Response.ok(
        config,
        headers: {'Content-Type': contentType},
      );
    });

    // OPTIONAL: Stub for future media serving (e.g., wallpaper image)
    // For now, returns a placeholder response — replace with actual file serving later
    router.get('/media/<file>', (Request request, String file) async {
      return Response.ok('Media placeholder: $file (implement file serving here)');
    });

    // Bind and start the server
    final server = await shelf_io.serve(router, '0.0.0.0', 8080);
    print('Provisioning server running at http://$myIp:${server.port}');

    return 'http://$myIp:8080';
  }
}
