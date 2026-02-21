import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/mustache_template_service.dart';

class ProvisioningServer {
  static final ProvisioningServer instance = ProvisioningServer._();
  ProvisioningServer._();
  static HttpServer? _server;
  static String? _serverUrl;

  static String? get serverUrl => _serverUrl;

  Future<String> start() async {
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
      return Response.ok(content, headers: {
        'Content-Type': 'text/plain',
        'Access-Control-Allow-Origin': '*',
      });
    });

    try {
      _server = await shelf_io.serve(router, '0.0.0.0', 8080);
      _serverUrl = 'http://$myIp:8080';
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
      print('Server stopped');
    }
  }
}
