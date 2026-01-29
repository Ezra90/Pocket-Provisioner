import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';

class ProvisioningServer {
  
  /// Starts the HTTP Server on Port 8080.
  /// Returns the full URL (e.g. http://192.168.1.50:8080)
  Future<String> start() async {
    final router = Router();
    final info = NetworkInfo();
    final myIp = await info.getWifiIP() ?? "0.0.0.0";

    // -- ROUTE 1: Config Request Handler --
    // Catches requests for MAC addresses (e.g., /001565112233.cfg)
    router.get('/<filename>', (Request req, String filename) async {
      
      // 1. Sanitize MAC: Remove file extensions and colons
      // e.g., "00:15:65:aa:bb:cc.cfg" -> "001565AABBCC"
      String cleanMac = filename
          .replaceAll(RegExp(r'\.(cfg|xml|boot)'), '')
          .replaceAll(':', '')
          .replaceAll('%3A', '')
          .toUpperCase();

      print("LOG: Request for $filename -> Parsed MAC: $cleanMac");

      // 2. Ignore generic Polycom boot files (Optional optimization)
      if (cleanMac.contains("000000000000")) {
        return Response.notFound("Generic boot config skipped.");
      }

      // 3. Database Lookup
      final Device? device = await DatabaseHelper.instance.getDeviceByMac(cleanMac);

      if (device == null) {
        return Response.notFound('Device MAC not found in Provisioning List.');
      }

      // 4. Load & Populate Template
      String rawTemplate = DeviceTemplates.getTemplateForModel(device.model);
      String contentType = DeviceTemplates.getContentType(device.model);

      String config = rawTemplate
          .replaceAll('{{label}}', device.label)
          .replaceAll('{{extension}}', device.extension)
          .replaceAll('{{secret}}', device.secret)
          .replaceAll('{{local_ip}}', myIp)
          .replaceAll('{{target_url}}', DeviceTemplates.telstraTarget);

      return Response.ok(config, headers: {'content-type': contentType});
    });

    // -- Start Listening --
    // We bind to '0.0.0.0' to allow connections from external devices (Phones)
    var server = await shelf_io.serve(router, '0.0.0.0', 8080);
    return "http://$myIp:${server.port}";
  }
}
