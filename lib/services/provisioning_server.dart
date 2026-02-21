import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';
import '../services/button_layout_service.dart';
import '../models/button_key.dart'; 

class ProvisioningServer {
  static final ProvisioningServer instance = ProvisioningServer._();
  ProvisioningServer._();
  static HttpServer? _server;

  Future<String> start() async {
    await stop();

    final router = Router();
    final info = NetworkInfo();
    String? myIp = await info.getWifiIP();
    myIp ??= '0.0.0.0'; 

    final prefs = await SharedPreferences.getInstance();
    
    // 1. Wallpaper Logic
    final String? publicBgUrl = prefs.getString('public_wallpaper_url');
    final String finalWallpaperUrl = (publicBgUrl != null && publicBgUrl.startsWith('http'))
        ? publicBgUrl
        : "http://$myIp:8080/media/custom_bg.png";

    // 2. Server Hop Logic
    final String targetUrl = prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget;

    // 3. SIP Server Logic (Manual vs Auto)
    final String? manualSipServer = prefs.getString('sip_server_address');
    final String finalSipServer = (manualSipServer != null && manualSipServer.isNotEmpty)
        ? manualSipServer
        : myIp; // Default to Android IP if blank

    // --- CONFIG HANDLER ---
    router.get('/<filename>', (Request request, String filename) async {
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
        return Response.notFound('Device not configured');
      }

      final (rawTemplate, contentType) = await DeviceTemplates.getTemplateAndContentType(device.model);

      // Build extToLabel fresh on each request so CSV imports are reflected immediately
      final List<Device> allDevices = await DatabaseHelper.instance.getAllDevices();
      final Map<String, String> extToLabel = {
        for (var d in allDevices) d.extension: d.label.isNotEmpty ? d.label : d.extension,
      };

      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp!)
          .replaceAll('{{sip_server_url}}', finalSipServer) // <--- NEW INJECTION
          .replaceAll('{{wallpaper_url}}', finalWallpaperUrl)
          .replaceAll('{{target_url}}', targetUrl);

      // Button Logic
      final List<ButtonKey> layout = await ButtonLayoutService.getLayoutForModel(device.model);
      final bool isYealink = !device.model.toUpperCase().contains('VVX') && 
                             !device.model.toUpperCase().contains('CISCO') &&
                             !device.model.toUpperCase().contains('EDGE');

      if (isYealink) {
        String dssSection = '';
        for (final key in layout) {
          if (key.type == 'none' || key.value.isEmpty) continue;
          final String typeCode = switch (key.type) {
            'blf' => '16', 'speeddial' => '13', 'line' => '15', _ => '0',            
          };
          final String effectiveLabel = key.label.isNotEmpty ? key.label : (extToLabel[key.value] ?? key.value);
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
    router.get('/media/<file>', (Request request, String file) async {
       final directory = await getApplicationDocumentsDirectory();
       final filePath = p.join(directory.path, file);
       final imageFile = File(filePath);

       if (await imageFile.exists()) {
         final bytes = await imageFile.readAsBytes();
         final mime = file.endsWith('.png') ? 'image/png' : 'image/jpeg';
         return Response.ok(bytes, headers: {'Content-Type': mime});
       } else {
         return Response.notFound('Image not found');
       }
    });

    try {
      _server = await shelf_io.serve(router, '0.0.0.0', 8080);
      print('Server running: http://$myIp:8080');
      return 'http://$myIp:8080';
    } catch (e) {
      print("Error starting server: $e");
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('Server stopped');
    }
  }
}
