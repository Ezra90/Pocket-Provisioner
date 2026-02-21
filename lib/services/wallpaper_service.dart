import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/device_templates.dart';

/// Holds metadata about a processed wallpaper entry.
class WallpaperInfo {
  final String name;           // e.g., "BunningsT4X"
  final String resizedPath;    // full path to resized file
  final String? originalPath;  // full path to original (if it exists)
  final String filename;       // e.g., "BunningsT4X_480x272.png"
  final int fileSize;

  const WallpaperInfo({
    required this.name,
    required this.resizedPath,
    this.originalPath,
    required this.filename,
    required this.fileSize,
  });
}

class WallpaperService {
  /// Regex that extracts the custom name from a resized wallpaper filename.
  /// Matches everything before the final `_{width}x{height}.` suffix.
  static final RegExp _resizedNamePattern = RegExp(r'^(.+)_\d+x\d+\.');

  /// Regex that captures width and height from a resized wallpaper filename.
  static final RegExp dimensionPattern = RegExp(r'_(\d+)x(\d+)\.');

  /// Directory for resized (served) wallpapers
  static Future<Directory> _mediaDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Directory for original source images
  static Future<Directory> _originalDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'media', 'original'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Process and save a wallpaper with a custom name.
  /// Stores the original in media/original/{name}_original.{ext}
  /// Stores the resized version in media/{name}_{width}x{height}.png
  /// Returns the resized filename (for use in config URLs).
  static Future<String> processAndSaveWallpaper(
      String sourcePath, WallpaperSpec spec, String customName) async {
    final File originalFile = File(sourcePath);
    final List<int> bytes = await originalFile.readAsBytes();

    // Decode image (supports jpg, png, gif, etc.)
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception("Could not decode image file");

    // Resize to exact fit
    img.Image resized = img.copyResize(
      image,
      width: spec.width,
      height: spec.height,
      interpolation: img.Interpolation.cubic,
    );

    // Save original preserving extension
    final origDir = await _originalDir();
    final srcExt = p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.png';
    final origFilename = '${customName}_original$srcExt';
    final origFile = File(p.join(origDir.path, origFilename));
    await origFile.writeAsBytes(bytes);

    // Save resized as PNG
    final mediaDir = await _mediaDir();
    final resizedFilename = '${customName}_${spec.width}x${spec.height}.png';
    final resizedFile = File(p.join(mediaDir.path, resizedFilename));
    await resizedFile.writeAsBytes(img.encodePng(resized));

    return resizedFilename;
  }

  /// List all wallpapers in the media directory (resized files only, not originals).
  static Future<List<WallpaperInfo>> listWallpapers() async {
    final mediaDir = await _mediaDir();
    final origDir = await _originalDir();

    final files = mediaDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'))
        .toList();

    final List<WallpaperInfo> result = [];
    for (final file in files) {
      final filename = p.basename(file.path);
      // Extract name: everything before the last _WxH segment
      final nameMatch = _resizedNamePattern.firstMatch(filename);
      final name = nameMatch != null ? nameMatch.group(1)! : filename;

      // Find matching original
      final origFiles = origDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('${name}_original'))
          .toList();
      final origPath = origFiles.isNotEmpty ? origFiles.first.path : null;

      final stat = await file.stat();
      result.add(WallpaperInfo(
        name: name,
        resizedPath: file.path,
        originalPath: origPath,
        filename: filename,
        fileSize: stat.size,
      ));
    }
    return result;
  }

  /// Delete a wallpaper (both resized and its original).
  static Future<void> deleteWallpaper(String filename) async {
    final mediaDir = await _mediaDir();
    final origDir = await _originalDir();

    final resizedFile = File(p.join(mediaDir.path, filename));
    if (await resizedFile.exists()) await resizedFile.delete();

    // Extract name to find original
    final nameMatch = _resizedNamePattern.firstMatch(filename);
    if (nameMatch != null) {
      final name = nameMatch.group(1)!;
      final origFiles = origDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('${name}_original'))
          .toList();
      for (final f in origFiles) {
        await f.delete();
      }
    }
  }

  /// Rename a wallpaper (both resized and original files).
  static Future<String> renameWallpaper(String oldFilename, String newName, WallpaperSpec spec) async {
    final mediaDir = await _mediaDir();
    final origDir = await _originalDir();

    // Rename resized file
    final oldResized = File(p.join(mediaDir.path, oldFilename));
    final newResizedFilename = '${newName}_${spec.width}x${spec.height}.png';
    final newResized = File(p.join(mediaDir.path, newResizedFilename));
    if (await oldResized.exists()) {
      await oldResized.rename(newResized.path);
    }

    // Rename original
    final oldNameMatch = _resizedNamePattern.firstMatch(oldFilename);
    if (oldNameMatch != null) {
      final oldName = oldNameMatch.group(1)!;
      final origFiles = origDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('${oldName}_original'))
          .toList();
      for (final f in origFiles) {
        final ext = p.extension(f.path);
        final newOrigPath = p.join(origDir.path, '${newName}_original$ext');
        await f.rename(newOrigPath);
      }
    }

    return newResizedFilename;
  }

  /// Re-process an original file with a (potentially different) spec.
  static Future<String> reprocessFromOriginal(String name, WallpaperSpec newSpec) async {
    final origDir = await _originalDir();
    final origFiles = origDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('${name}_original'))
        .toList();

    if (origFiles.isEmpty) throw Exception('No original found for "$name"');

    return processAndSaveWallpaper(origFiles.first.path, newSpec, name);
  }

  /// Get the resized file path for a wallpaper by filename.
  static Future<String?> getResizedPath(String filename) async {
    final mediaDir = await _mediaDir();
    final file = File(p.join(mediaDir.path, filename));
    if (await file.exists()) return file.path;
    return null;
  }
}
