import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/device_templates.dart';

class WallpaperService {
  
  /// Processes the uploaded image:
  /// 1. Decodes it.
  /// 2. Resizes it to fit the handset spec (e.g. 480x272).
  /// 3. Saves it as 'custom_bg.png' in the app's document folder.
  /// Returns the file path of the saved image.
  static Future<String> processAndSaveWallpaper(String sourcePath, WallpaperSpec spec) async {
    final File originalFile = File(sourcePath);
    final List<int> bytes = await originalFile.readAsBytes();
    
    // Decode image (supports jpg, png, gif, etc.)
    img.Image? image = img.decodeImage(bytes);
    
    if (image == null) throw Exception("Could not decode image file");

    // Resize logic: Force exact fit (Yealink/Polycom need exact resolutions)
    img.Image resized = img.copyResize(
      image, 
      width: spec.width, 
      height: spec.height,
      interpolation: img.Interpolation.cubic // High quality resize
    );

    // Get App Documents Directory
    final directory = await getApplicationDocumentsDirectory();
    final String targetPath = p.join(directory.path, 'custom_bg.png'); // Standardized name

    // Encode as PNG (safest format for all VoIP phones)
    final File resultFile = File(targetPath);
    await resultFile.writeAsBytes(img.encodePng(resized));

    return targetPath;
  }
}
