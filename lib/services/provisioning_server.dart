import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';

class ProvisioningServer {
  
  Future<String> start() async {
    final router = Router();
    final info = NetworkInfo();
    final myIp = await info.getWifiIP() ?? "0.0.0.0";

    final prefs = await SharedPreferences.getInstance();
    
    // 1. Get Wallpaper URL
    final String? publicBgUrl = prefs.getString('public_wallpaper_url');
    final String finalWallpaperUrl = (publicBgUrl != null && publicBgUrl.isNotEmpty) 
        ? publicBgUrl 
        : "http://$myIp:8080/media/custom_bg.png";

    // 2. Get Target Provisioning URL (The Hop)
    final String targetUrl = prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget;

    router.get('/<filename>', (Request req, String filename) async {
      
      String cleanMac = filename
          .replaceAll(RegExp(r'\.(cfg|xml|boot)'), '')
          .replaceAll(':', '')
          .replaceAll('%3A', '')
          .toUpperCase();

      print("LOG: Request for $filename -> Parsed MAC: $cleanMac");

      if (cleanMac.contains("000000000000")) {
        return Response.notFound("Generic boot config skipped.");
      }

      final Device? device = await DatabaseHelper.instance.getDeviceByMac(cleanMac);

      if (device == null) {
        return Response.notFound('Device MAC not found in Provisioning List.');
      }

      String rawTemplate = await DeviceTemplates.getTemplateForModel(device.model);
      String contentType = await DeviceTemplates.getContentType(device.model);

      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp)
          .replaceAll('{{wallpaper_url}}', finalWallpaperUrl)
          .replaceAll('{{target_url}}', targetUrl); // <--- INJECTED FROM SETTINGS

      return Response.ok(config, headers: {'content-type': contentType});
    });

    router.get('/media/<filename>', (Request req, String filename) {
        return Response.ok("Binary Image Data Would Go Here"); 
    });

    var server = await shelf_io.serve(router, '0.0.0.0', 8080);
    return "http://$myIp:${server.port}";
  }
}
