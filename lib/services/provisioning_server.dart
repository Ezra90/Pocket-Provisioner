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
import '../models/button_key.dart'; 

class ProvisioningServer {
  Future<String> start() async {
    final router = Router();

    final info = NetworkInfo();
    final String myIp = await info.getWifiIP() ?? '0.0.0.0';

    final prefs = await SharedPreferences.getInstance();
    final String? publicBgUrl = prefs.getString('public_wallpaper_url');
    // Default to local server if no public URL provided
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
    // Handles: 
    // - Yealink: 001565aabbcc.cfg
    // - Polycom: 0004f2aabbcc.cfg or .xml
    // - Cisco: SEP001122334455.cnf.xml
    router.get('/<filename>', (Request request, String filename) async {
      
      // 1. CLEAN MAC ADDRESS
      // Removes 'SEP' (Cisco), '0000' (Generics), and extensions
      String cleanMac = filename
          .toUpperCase()
          .replaceAll('SEP', '') // Handle Cisco Prefix
          .replaceAll(RegExp(r'[:\.\-\s%3A]'), '')
          .replaceAll(RegExp(r'\.(CFG|XML|BOOT|CNF)$', caseSensitive: false), '');

      print('LOG: Request $filename → MAC $cleanMac');

      // Skip generic manufacturer requests
      if (cleanMac.length < 12 || cleanMac == '000000000000' || cleanMac.startsWith('Y000')) {
        return Response.notFound('Generic request skipped');
      }

      // 2. LOOKUP DEVICE
      final Device? device = await DatabaseHelper.instance.getDeviceByMac(cleanMac);
      if (device == null) {
        print('LOG: Device not found for MAC $cleanMac');
        return Response.notFound('MAC $cleanMac not in list');
      }

      // 3. LOAD TEMPLATE
      String rawTemplate = await DeviceTemplates.getTemplateForModel(device.model);
      String contentType = await DeviceTemplates.getContentType(device.model);

      // 4. CORE VARIABLE REPLACEMENT
      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp)
          .replaceAll('{{wallpaper_url}}', finalWallpaperUrl)
          .replaceAll('{{target_url}}', targetUrl);

      // 5. BUTTON / DSS KEY GENERATION
      final List<ButtonKey> layout = await ButtonLayoutService.getLayoutForModel(device.model);
      
      // Detect Manufacturer for specific Key Logic
      final bool isYealink = !device.model.toUpperCase().contains('VVX') && 
                             !device.model.toUpperCase().contains('CISCO') &&
                             !device.model.toUpperCase().contains('EDGE');

      if (isYealink) {
        String dssSection = '';
        for (final key in layout) {
          if (key.type == 'none' || key.value.isEmpty) continue;

          // Yealink Type Codes:
          // 16 = BLF, 13 = Speed Dial, 15 = Line Key
          final String typeCode = switch (key.type) {
            'blf' => '16',       
            'speeddial' => '13',  
            'line' => '15',       
            _ => '0',            
          };

          // Label fallback: Custom -> Device Name -> Extension
          final String effectiveLabel = key.label.isNotEmpty
              ? key.label
              : (extToLabel[key.value] ?? key.value);

          // Generate Line Key Config
          dssSection += '''
linekey.${key.id}.type = $typeCode
linekey.${key.id}.value = ${key.value}
linekey.${key.id}.label = $effectiveLabel
linekey.${key.id}.line = 1
${key.type == 'blf' ? 'linekey.${key.id}.pickup_value = **' : ''} 
''';
        }
        config = config.replaceAll('{{dss_keys}}', dssSection.trim());
      } else {
        // Clear placeholder for non-Yealink devices (Poly/Cisco button mapping is complex)
        config = config.replaceAll('{{dss_keys}}', '');
      }

      return Response.ok(config, headers: {'Content-Type': contentType});
    });

    // Simple Media Stub for local wallpapers
    router.get('/media/<file>', (Request request, String file) async {
       return Response.ok('Media file: $file (implement binary serving here if needed)');
    });

    final server = await shelf_io.serve(router, '0.0.0.0', 8080);
    print('Server online: http://$myIp:8080');

    return 'http://$myIp:8080';
  }
}
