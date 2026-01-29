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
  // Static instance to control the server across the app
  static HttpServer? _server;

  Future<String> start() async {
    // Ensure any previous instance is killed before starting
    await stop();

    final router = Router();
    final info = NetworkInfo();
    String? myIp = await info.getWifiIP();
    myIp ??= '0.0.0.0'; 

    final prefs = await SharedPreferences.getInstance();
    final String? publicBgUrl = prefs.getString('public_wallpaper_url');
    final String finalWallpaperUrl = (publicBgUrl != null && publicBgUrl.isNotEmpty)
        ? publicBgUrl
        : "http://$myIp:8080/media/custom_bg.png";

    final String targetUrl = prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget;

    // Pre-load devices for label mapping
    final List<Device> allDevices = await DatabaseHelper.instance.getAllDevices();
    final Map<String, String> extToLabel = {
      for (var d in allDevices) d.extension: d.label.isNotEmpty ? d.label : d.extension,
    };

    // --- CONFIG HANDLER ---
    router.get('/<filename>', (Request request, String filename) async {
      // MAC Sanitization
      String cleanMac = filename
          .toUpperCase()
          .replaceAll('SEP', '')
          .replaceAll(RegExp(r'[:\.\-\s%3A]'), '')
          .replaceAll(RegExp(r'\.(CFG|XML|BOOT|CNF)$', caseSensitive: false), '');

      print('REQ: $filename -> MAC: $cleanMac');

      if (cleanMac.length < 12 || cleanMac == '000000000000') {
        return Response.notFound('Generic request skipped');
      }

      final Device? device = await DatabaseHelper.instance.getDeviceByMac(cleanMac);
      if (device == null) {
        return Response.notFound('Device not configured in app');
      }

      // Template Processing
      String rawTemplate = await DeviceTemplates.getTemplateForModel(device.model);
      String contentType = await DeviceTemplates.getContentType(device.model);

      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp!)
          .replaceAll('{{wallpaper_url}}', finalWallpaperUrl)
          .replaceAll('{{target_url}}', targetUrl);

      // Button/Key Injection
      final List<ButtonKey> layout = await ButtonLayoutService.getLayoutForModel(device.model);
      final bool isYealink = !device.model.toUpperCase().contains('VVX') && 
                             !device.model.toUpperCase().contains('CISCO') &&
                             !device.model.toUpperCase().contains('EDGE');

      if (isYealink) {
        String dssSection = '';
        for (final key in layout) {
          if (key.type == 'none' || key.value.isEmpty) continue;
          
          final String typeCode = switch (key.type) {
            'blf' => '16',       
            'speeddial' => '13',  
            'line' => '15',       
            _ => '0',            
          };

          final String effectiveLabel = key.label.isNotEmpty
              ? key.label
              : (extToLabel[key.value] ?? key.value);

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
        config = config.replaceAll('{{dss_keys}}', '');
      }

      return Response.ok(config, headers: {
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*',
      });
    });

    // --- MEDIA HANDLER ---
    router.get('/media/<file>', (Request request, String file) {
       // Placeholder: in a real app, serve from getApplicationDocumentsDirectory
       return Response.ok('Image data');
    });

    try {
      _server = await shelf_io.serve(router, '0.0.0.0', 8080);
      print('Server running on port 8080');
      return 'http://$myIp:8080';
    } catch (e) {
      print("Error starting server: $e");
      throw e;
    }
  }

  // Stop method to release the port
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('Server stopped');
    }
  }
}
