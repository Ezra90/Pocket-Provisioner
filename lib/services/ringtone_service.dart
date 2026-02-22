import 'dart:io';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
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
/// All ringtones are stored as 8kHz / 16-bit / mono PCM WAV files.
class RingtoneService {
  static const int _maxSizeBytes = 1024 * 1024; // 1 MB
  static const int _maxDurationSeconds = 12;

  static Future<Directory> _ringtonesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'ringtones'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Converts any audio file to phone-compatible WAV (PCM 16-bit LE, 8 kHz, mono)
  /// and stores it in the ringtones directory.
  /// If the output exceeds 1 MB it is auto-trimmed to [_maxDurationSeconds].
  /// Returns the output filename (e.g. "MyRingtone.wav").
  static Future<String> convertAndSave(
      String sourcePath, String customName) async {
    final dir = await _ringtonesDir();
    final outputFilename = '$customName.wav';
    final outputPath = p.join(dir.path, outputFilename);

    // Convert to 8 kHz, 16-bit, mono PCM WAV
    final session = await FFmpegKit.execute(
      '-y -i "$sourcePath" -ar 8000 -ac 1 -sample_fmt s16 "$outputPath"',
    );

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getOutput();
      throw Exception('FFmpeg conversion failed: $logs');
    }

    // If output exceeds 1 MB, trim to max duration
    final outFile = File(outputPath);
    if (await outFile.exists()) {
      final size = await outFile.length();
      if (size > _maxSizeBytes) {
        final trimPath = p.join(dir.path, '${customName}_tmp.wav');
        final trimSession = await FFmpegKit.execute(
          '-y -i "$outputPath" -t $_maxDurationSeconds '
          '-ar 8000 -ac 1 -sample_fmt s16 "$trimPath"',
        );
        final trimCode = await trimSession.getReturnCode();
        if (ReturnCode.isSuccess(trimCode)) {
          await outFile.delete();
          await File(trimPath).rename(outputPath);
        }
      }
    }

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
