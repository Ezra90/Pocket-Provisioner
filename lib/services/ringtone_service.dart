import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Metadata for a single ringtone file.
class RingtoneInfo {
  final String filename;
  final String name;
  final String path;
  final int sizeBytes;

  const RingtoneInfo({
    required this.filename,
    required this.name,
    required this.path,
    required this.sizeBytes,
  });
}

/// Handles ringtone file management.
/// Ringtones must be provided as WAV files. VoIP phones typically require
/// PCM WAV files (e.g. 8 kHz / 16-bit / mono) — ensure your WAV file matches
/// the specifications required by your phone model. Files are stored in the
/// application documents directory under a dedicated sub-folder.
class RingtoneService {
  static const int _maxSizeBytes = 1024 * 1024; // 1 MB

  static Future<Directory> _ringtonesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'ringtones'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies a WAV file into the ringtones directory under [customName].wav.
  /// Throws if the source is not a WAV file or exceeds [_maxSizeBytes].
  /// Returns the output filename (e.g. "MyRingtone.wav").
  static Future<String> convertAndSave(
      String sourcePath, String customName) async {
    if (!sourcePath.toLowerCase().endsWith('.wav')) {
      throw Exception('Only WAV files are supported. Please provide a .wav file.');
    }

    final sourceFile = File(sourcePath);
    final size = await sourceFile.length();
    if (size > _maxSizeBytes) {
      throw Exception(
          'File exceeds the 1 MB limit (${(size / 1024).toStringAsFixed(0)} KB). '
          'Please use a shorter audio clip.');
    }

    final dir = await _ringtonesDir();
    final outputFilename = '$customName.wav';
    final outputPath = p.join(dir.path, outputFilename);
    await sourceFile.copy(outputPath);
    return outputFilename;
  }

  /// Lists all WAV files in the ringtones directory.
  static Future<List<RingtoneInfo>> listRingtones() async {
    final dir = await _ringtonesDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.wav'))
        .toList();

    final result = <RingtoneInfo>[];
    for (final file in files) {
      final filename = p.basename(file.path);
      final stat = await file.stat();
      result.add(RingtoneInfo(
        filename: filename,
        name: p.basenameWithoutExtension(file.path),
        path: file.path,
        sizeBytes: stat.size,
      ));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// Deletes a ringtone file by filename.
  static Future<void> deleteRingtone(String filename) async {
    final dir = await _ringtonesDir();
    final file = File(p.join(dir.path, filename));
    if (await file.exists()) await file.delete();
  }

  /// Renames a ringtone file.  Returns the new filename.
  static Future<String> renameRingtone(
      String oldFilename, String newName) async {
    final dir = await _ringtonesDir();
    final oldFile = File(p.join(dir.path, oldFilename));
    final newFilename = '$newName.wav';
    final newFile = File(p.join(dir.path, newFilename));
    if (await oldFile.exists()) await oldFile.rename(newFile.path);
    return newFilename;
  }
}
