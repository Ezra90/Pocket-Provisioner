import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'app_directories.dart';

/// Parsed WAV header metadata returned after a file is imported.
class WavInfo {
  final int sampleRate;    // e.g. 8000, 16000, 44100
  final int channels;      // 1 = mono, 2 = stereo
  final int bitsPerSample; // typically 8 or 16
  final bool isPcm;        // true when audio-format tag == 1 (Linear PCM)
  final int durationMs;    // approximate duration in milliseconds

  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.isPcm,
    required this.durationMs,
  });

  /// True when the file is ready for use on standard VoIP phones without
  /// further processing (PCM, 8 kHz or 16 kHz, 16-bit, mono).
  bool get isCompatible =>
      isPcm &&
      (sampleRate == 8000 || sampleRate == 16000) &&
      bitsPerSample == 16 &&
      channels == 1;

  /// Human-readable summary, e.g. "PCM, 44100 Hz, 16-bit, Stereo".
  String get formatString =>
      '${isPcm ? "PCM" : "Non-PCM"}, $sampleRate Hz, '
      '${bitsPerSample}-bit, ${channels == 1 ? "Mono" : "Stereo"}';

  /// Returns a user-facing warning string when the format may not be
  /// supported by the phone, or null when the file looks fine.
  String? get compatibilityNote {
    if (!isPcm) return 'Non-PCM format — may not play on VoIP phones';
    if (bitsPerSample != 16) {
      return '$bitsPerSample-bit audio — phones typically require 16-bit';
    }
    if (sampleRate != 8000 && sampleRate != 16000) {
      return '$sampleRate Hz — 8 kHz or 16 kHz is recommended for phones';
    }
    // Stereo is fine here; it will be auto-converted to mono on import.
    return null;
  }
}

/// Holds the result of [RingtoneService.convertAndSave].
class RingtoneSaveResult {
  final String filename; // output filename, e.g. "MyRing.wav"
  final WavInfo? wavInfo; // null when the WAV header could not be parsed

  const RingtoneSaveResult(this.filename, this.wavInfo);
}

/// Metadata for a single ringtone file listed from the ringtones directory.
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

/// Handles ringtone file management for VoIP handset provisioning.
///
/// Ringtones must be provided as WAV files.  On import:
///   • The untouched original is cached in  `ringtones/original/` so it can
///     be re-processed later if requirements change.
///   • Stereo 16-bit PCM WAV files are automatically down-mixed to mono.
///   • The processed file is served from `ringtones/` by the HTTP server.
class RingtoneService {
  static const int _maxSizeBytes = 1024 * 1024; // 1 MB

  // ── Directory helpers ──────────────────────────────────────────────────────

  static Future<Directory> _ringtonesDir() => AppDirectories.ringtoneDir();

  /// Originals sub-folder — untouched source files cached for re-processing.
  static Future<Directory> _originalsDir() => AppDirectories.ringtoneOriginalDir();

  // ── WAV header parsing ─────────────────────────────────────────────────────

  /// Parses a RIFF/WAV header and returns format metadata, or null on failure.
  static WavInfo? parseWavHeader(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;

    int offset = 12;
    int? audioFormat, channels, sampleRate, bitsPerSample, dataSizeBytes;

    while (offset + 8 <= bytes.length) {
      final chunkId =
          String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize =
          ByteData.sublistView(bytes, offset + 4, offset + 8)
              .getUint32(0, Endian.little);

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        final end = (offset + 8 + chunkSize).clamp(0, bytes.length);
        final bd = ByteData.sublistView(bytes, offset + 8, end);
        audioFormat = bd.getUint16(0, Endian.little);
        channels = bd.getUint16(2, Endian.little);
        sampleRate = bd.getUint32(4, Endian.little);
        bitsPerSample = bd.getUint16(14, Endian.little);
      } else if (chunkId == 'data') {
        dataSizeBytes = chunkSize;
      }

      // RIFF chunks are word-aligned
      final aligned = chunkSize + (chunkSize.isOdd ? 1 : 0);
      offset += 8 + aligned;
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null) {
      return null;
    }

    final bytesPerSec =
        sampleRate * channels * (bitsPerSample ~/ 8).clamp(1, 4);
    final durationMs = (bytesPerSec > 0 && dataSizeBytes != null)
        ? (dataSizeBytes * 1000 ~/ bytesPerSec)
        : 0;

    return WavInfo(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      isPcm: audioFormat == 1,
      durationMs: durationMs,
    );
  }

  // ── Stereo → mono conversion ───────────────────────────────────────────────

  /// Down-mixes a 16-bit stereo PCM WAV to mono by averaging L + R channels.
  /// Returns the original bytes unchanged when conversion is not applicable.
  static Uint8List convertStereoToMono(Uint8List bytes) {
    final info = parseWavHeader(bytes);
    if (info == null ||
        !info.isPcm ||
        info.channels != 2 ||
        info.bitsPerSample != 16) {
      return bytes;
    }

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId =
          String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize =
          ByteData.sublistView(bytes, offset + 4, offset + 8)
              .getUint32(0, Endian.little);

      if (chunkId == 'data') {
        final dataOffset = offset + 8;
        final safeSize = chunkSize.clamp(0, bytes.length - dataOffset);
        const stereoFrame = 4; // 2 bytes L + 2 bytes R
        final frameCount = safeSize ~/ stereoFrame;

        final monoData = Uint8List(frameCount * 2);
        final inBd = ByteData.sublistView(
            bytes, dataOffset, dataOffset + frameCount * stereoFrame);
        final outBd = ByteData.sublistView(monoData);

        for (int i = 0; i < frameCount; i++) {
          final left = inBd.getInt16(i * 4, Endian.little);
          final right = inBd.getInt16(i * 4 + 2, Endian.little);
          final mono = ((left + right) >> 1).clamp(-32768, 32767);
          outBd.setInt16(i * 2, mono, Endian.little);
        }

        // Build new RIFF/WAV with mono fmt chunk
        const fmtSize = 16;
        final newDataSize = frameCount * 2;
        final result = Uint8List(12 + 8 + fmtSize + 8 + newDataSize);
        final bd = ByteData.sublistView(result);

        result.setRange(0, 4, 'RIFF'.codeUnits);
        bd.setUint32(4, result.length - 8, Endian.little);
        result.setRange(8, 12, 'WAVE'.codeUnits);

        result.setRange(12, 16, 'fmt '.codeUnits);
        bd.setUint32(16, fmtSize, Endian.little);
        bd.setUint16(20, 1, Endian.little);                        // PCM
        bd.setUint16(22, 1, Endian.little);                        // 1 ch
        bd.setUint32(24, info.sampleRate, Endian.little);
        bd.setUint32(28, info.sampleRate * 2, Endian.little);      // byteRate
        bd.setUint16(32, 2, Endian.little);                        // blockAlign
        bd.setUint16(34, 16, Endian.little);                       // 16-bit

        result.setRange(36, 40, 'data'.codeUnits);
        bd.setUint32(40, newDataSize, Endian.little);
        result.setRange(44, 44 + newDataSize, monoData);

        return result;
      }

      final aligned = chunkSize + (chunkSize.isOdd ? 1 : 0);
      offset += 8 + aligned;
    }

    return bytes; // fallback — data chunk not found
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Imports a WAV file into the ringtones library.
  ///
  /// Steps performed:
  ///   1. Validates extension (.wav) and file size (≤ 1 MB).
  ///   2. Saves the untouched original to `ringtones/original/<customName>.wav`
  ///      so it can be re-imported later if needed.
  ///   3. If the file is stereo 16-bit PCM, auto-converts to mono.
  ///   4. Writes the processed file to `ringtones/<customName>.wav`.
  ///
  /// Returns a [RingtoneSaveResult] with the output filename and WAV metadata.
  /// Throws on unsupported file type or size violation.
  static Future<RingtoneSaveResult> convertAndSave(
      String sourcePath, String customName) async {
    if (!sourcePath.toLowerCase().endsWith('.wav')) {
      throw Exception(
          'Only WAV files are supported. Please provide a .wav file.');
    }

    final sourceFile = File(sourcePath);
    final size = await sourceFile.length();
    if (size > _maxSizeBytes) {
      throw Exception(
          'File exceeds the 1 MB limit (${(size / 1024).toStringAsFixed(0)} KB). '
          'Please use a shorter audio clip.');
    }

    Uint8List bytes = await sourceFile.readAsBytes();
    final info = parseWavHeader(bytes);

    // Cache the original before any conversion
    final origDir = await _originalsDir();
    await File(p.join(origDir.path, '$customName.wav')).writeAsBytes(bytes);

    // Auto down-mix stereo → mono when safe to do so
    if (info != null &&
        info.isPcm &&
        info.channels == 2 &&
        info.bitsPerSample == 16) {
      bytes = convertStereoToMono(bytes);
    }

    final dir = await _ringtonesDir();
    final outputFilename = '$customName.wav';
    await File(p.join(dir.path, outputFilename)).writeAsBytes(bytes);

    return RingtoneSaveResult(outputFilename, info);
  }

  /// Re-processes a ringtone from its cached original (applies stereo→mono
  /// if applicable).  Useful after the originals directory has been populated
  /// by a previous [convertAndSave] call.
  static Future<String> reprocessFromOriginal(String filename) async {
    final origDir = await _originalsDir();
    final origFile = File(p.join(origDir.path, filename));
    if (!await origFile.exists()) {
      throw Exception('No original cached for "$filename"');
    }

    Uint8List bytes = await origFile.readAsBytes();
    final info = parseWavHeader(bytes);
    if (info != null &&
        info.isPcm &&
        info.channels == 2 &&
        info.bitsPerSample == 16) {
      bytes = convertStereoToMono(bytes);
    }

    final dir = await _ringtonesDir();
    await File(p.join(dir.path, filename)).writeAsBytes(bytes);
    return filename;
  }

  /// Lists all WAV files in the ringtones directory (excluding the originals
  /// sub-folder).
  static Future<List<RingtoneInfo>> listRingtones() async {
    final dir = await _ringtonesDir();
    final allEntries = await dir.list().toList();
    final files = allEntries
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

  /// Deletes a ringtone (both the processed file and its cached original).
  static Future<void> deleteRingtone(String filename) async {
    final dir = await _ringtonesDir();
    final origDir = await _originalsDir();

    final file = File(p.join(dir.path, filename));
    if (await file.exists()) await file.delete();

    final orig = File(p.join(origDir.path, filename));
    if (await orig.exists()) await orig.delete();
  }

  /// Renames a ringtone (both the processed file and its cached original).
  /// Returns the new filename (e.g. "NewName.wav").
  static Future<String> renameRingtone(
      String oldFilename, String newName) async {
    final dir = await _ringtonesDir();
    final origDir = await _originalsDir();
    final newFilename = '$newName.wav';

    final oldFile = File(p.join(dir.path, oldFilename));
    if (await oldFile.exists()) {
      await oldFile.rename(File(p.join(dir.path, newFilename)).path);
    }

    final oldOrig = File(p.join(origDir.path, oldFilename));
    if (await oldOrig.exists()) {
      await oldOrig.rename(File(p.join(origDir.path, newFilename)).path);
    }

    return newFilename;
  }
}
