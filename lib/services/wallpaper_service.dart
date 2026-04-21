import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import 'app_directories.dart';

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
  static Future<Directory> _mediaDir() => AppDirectories.mediaDir();

  /// Directory for original source images
  static Future<Directory> _originalDir() => AppDirectories.mediaOriginalDir();

  /// Process and save a wallpaper with a custom name.
  /// Stores the original in media/original/{name}_original.{ext}
  /// Stores the resized version in media/{name}_{width}x{height}.png
  /// Returns the resized filename (for use in config URLs).
  static Future<String> processAndSaveWallpaper(
      String sourcePath, WallpaperSpec spec, String customName) async {
    final File originalFile = File(sourcePath);
    final Uint8List bytes = await originalFile.readAsBytes();

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

    final allEntries = await mediaDir.list().toList();
    final files = allEntries
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'))
        .toList();

    // List originals once rather than inside the per-file loop.
    final origEntries = await origDir.list().toList();
    final origFileList = origEntries.whereType<File>().toList();

    final List<WallpaperInfo> result = [];
    for (final file in files) {
      final filename = p.basename(file.path);
      // Extract name: everything before the last _WxH segment
      final nameMatch = _resizedNamePattern.firstMatch(filename);
      final name = nameMatch != null ? nameMatch.group(1)! : filename;

      // Find matching original
      final origPath = origFileList
          .where((f) => p.basename(f.path).startsWith('${name}_original'))
          .map((f) => f.path)
          .firstOrNull;
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
      final origEntries = await origDir.list().toList();
      final origFiles = origEntries
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
      final origEntries = await origDir.list().toList();
      final origFiles = origEntries
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
  /// Removes any existing resized files for [name] that are not referenced by
  /// a device in the database, so that changing dimensions does not leave stale
  /// entries behind while still preserving files that provisioned devices need.
  static Future<String> reprocessFromOriginal(String name, WallpaperSpec newSpec) async {
    final origDir = await _originalDir();
    final origEntries = await origDir.list().toList();
    final origFiles = origEntries
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('${name}_original'))
        .toList();

    if (origFiles.isEmpty) throw Exception('No original found for "$name"');

    // Collect the set of wallpaper filenames still referenced by devices so we
    // don't remove a file that a provisioned handset still needs.
    final allDevices = await DatabaseHelper.instance.getAllDevices();
    final referencedFiles = <String>{
      for (final d in allDevices)
        if (d.wallpaper != null && d.wallpaper!.startsWith('LOCAL:'))
          d.wallpaper!.substring('LOCAL:'.length),
    };

    // Delete unreferenced resized versions so a dimension change does not
    // leave orphaned files (e.g. switching from 480x272 to 800x480).
    final mediaDir = await _mediaDir();
    final mediaEntries = await mediaDir.list().toList();
    for (final f in mediaEntries.whereType<File>()) {
      final fname = p.basename(f.path);
      final nameMatch = _resizedNamePattern.firstMatch(fname);
      if (nameMatch != null && nameMatch.group(1) == name) {
        if (!referencedFiles.contains(fname)) {
          await f.delete();
        }
      }
    }

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
