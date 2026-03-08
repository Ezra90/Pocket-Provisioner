import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Metadata about a locally stored firmware file.
class FirmwareInfo {
  final String filename;
  final int sizeBytes;

  const FirmwareInfo({required this.filename, required this.sizeBytes});
}

/// Service that manages firmware files hosted by the provisioning server.
///
/// Firmware files are stored in `<appDocuments>/firmware/` and served at
/// `http://<server>/firmware/<filename>`.  Each phone brand expects a
/// specific file format:
///   • Yealink  — `.rom` binary, served at `static.firmware.url`
///   • Polycom  — `.ld`  binary, served at `updater.application.url`
///   • Cisco    — `.loads` manifest or binary, served at `<upgrade_rule>`
class FirmwareService {
  // ── Directory helpers ────────────────────────────────────────────────────

  static Future<Directory> _firmwareDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'firmware'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Copies [sourcePath] into the firmware directory using [filename] as the
  /// stored name.  The destination file is returned.
  static Future<File> save(String sourcePath, String filename) async {
    final dir = await _firmwareDir();
    final safe = p.basename(filename);
    final dest = File(p.join(dir.path, safe));
    await File(sourcePath).copy(dest.path);
    return dest;
  }

  /// Saves raw [bytes] into the firmware directory using [filename] as the
  /// stored name.  Used as a fallback when a direct file path is unavailable
  /// (e.g. Android content URIs returned by the file picker).
  static Future<File> saveBytes(Uint8List bytes, String filename) async {
    final dir = await _firmwareDir();
    final safe = p.basename(filename);
    final dest = File(p.join(dir.path, safe));
    await dest.writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// Lists all firmware files, sorted alphabetically by filename.
  static Future<List<FirmwareInfo>> listFirmware() async {
    final dir = await _firmwareDir();
    if (!await dir.exists()) return [];
    final files = (await dir.list().toList()).whereType<File>().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final result = <FirmwareInfo>[];
    for (final f in files) {
      final stat = await f.stat();
      result.add(FirmwareInfo(
        filename: p.basename(f.path),
        sizeBytes: stat.size,
      ));
    }
    return result;
  }

  /// Deletes the firmware file with [filename].
  static Future<void> deleteFirmware(String filename) async {
    final dir = await _firmwareDir();
    final file = File(p.join(dir.path, p.basename(filename)));
    if (await file.exists()) await file.delete();
  }

  /// Returns the full filesystem path for [filename] inside the firmware
  /// directory, or null if the file does not exist.
  static Future<String?> resolvePath(String filename) async {
    final dir = await _firmwareDir();
    final file = File(p.join(dir.path, p.basename(filename)));
    return await file.exists() ? file.path : null;
  }
}
