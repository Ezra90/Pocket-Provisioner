import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Centralised directory resolution for all Pocket Provisioner file stores.
///
/// User-facing content (ringtones, wallpapers, phonebook, firmware) is stored
/// in app-specific **external** storage so that Android file manager apps can
/// browse and drop files directly:
///
///   /storage/emulated/0/Android/data/<package>/files/
///
/// No special permissions are required — this path is part of the app's own
/// sandboxed external storage, accessible without root via the built-in Files
/// app on Android 10+.
///
/// When external storage is unavailable (iOS, or the storage volume is not
/// mounted) the implementation falls back to [getApplicationDocumentsDirectory].
///
/// Internal-only data (generated configs, custom templates) remains in app-
/// private internal storage and is not intended for manual editing.
class AppDirectories {
  // ── Result cache ─────────────────────────────────────────────────────────

  static Future<Directory>? _userBaseFuture;

  // ── Base directory resolution ─────────────────────────────────────────────

  static Future<Directory?> _externalBase() async {
    if (!Platform.isAndroid) return null;
    try {
      return await getExternalStorageDirectory();
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _internalBase() =>
      getApplicationDocumentsDirectory();

  /// Base directory for user-facing files.
  /// Prefers app-specific external storage (file-manager accessible) on Android;
  /// falls back to internal documents directory on other platforms.
  static Future<Directory> _userBase() {
    return _userBaseFuture ??= _resolveUserBase();
  }

  static Future<Directory> _resolveUserBase() async {
    final ext = await _externalBase();
    return ext ?? await _internalBase();
  }

  // ── User-facing directories (external storage on Android) ─────────────────

  /// Firmware binary files served at `/firmware/<filename>`.
  static Future<Directory> firmwareDir() async =>
      _ensure(p.join((await _userBase()).path, 'firmware'));

  /// Processed WAV ringtone files served at `/ringtones/<filename>`.
  static Future<Directory> ringtoneDir() async =>
      _ensure(p.join((await _userBase()).path, 'ringtones'));

  /// Cached original (pre-conversion) ringtone sources.
  static Future<Directory> ringtoneOriginalDir() async =>
      _ensure(p.join((await _userBase()).path, 'ringtones', 'original'));

  /// Resized wallpaper images served at `/media/<filename>`.
  static Future<Directory> mediaDir() async =>
      _ensure(p.join((await _userBase()).path, 'media'));

  /// Original (pre-resize) wallpaper source images.
  static Future<Directory> mediaOriginalDir() async =>
      _ensure(p.join((await _userBase()).path, 'media', 'original'));

  /// Phonebook XML files served at `/phonebook/<filename>`.
  static Future<Directory> phonebookDir() async =>
      _ensure(p.join((await _userBase()).path, 'phonebook'));

  // ── Internal-only directories ─────────────────────────────────────────────

  /// Auto-generated MAC config files (not intended for manual editing).
  static Future<Directory> configsDir() async =>
      _ensure(p.join((await _internalBase()).path, 'generated_configs'));

  /// Custom Mustache provisioning templates.
  static Future<Directory> templatesDir() async =>
      _ensure(p.join((await _internalBase()).path, 'custom_templates'));

  // ── Migration ─────────────────────────────────────────────────────────────

  /// Moves user-facing files from the legacy internal-storage layout to the
  /// new external-storage layout.  Safe to call on every startup — it skips
  /// any destination that already contains files.
  static Future<void> migrateToExternal() async {
    if (!Platform.isAndroid) return;
    final ext = await _externalBase();
    if (ext == null) return; // external not mounted — nothing to migrate

    final internal = await _internalBase();

    final migrations = <String, String>{
      p.join(internal.path, 'firmware'): p.join(ext.path, 'firmware'),
      p.join(internal.path, 'ringtones'): p.join(ext.path, 'ringtones'),
      p.join(internal.path, 'media'): p.join(ext.path, 'media'),
      p.join(internal.path, 'phonebook'): p.join(ext.path, 'phonebook'),
    };

    for (final entry in migrations.entries) {
      await _migrateDirectory(entry.key, entry.value);
    }
  }

  /// Copies every file under [srcPath] to [destPath], preserving the relative
  /// sub-directory structure, then deletes the source files.
  ///
  /// Skips the migration when:
  ///   • [srcPath] does not exist, or
  ///   • [destPath] already contains at least one file (already migrated).
  static Future<void> _migrateDirectory(
      String srcPath, String destPath) async {
    final src = Directory(srcPath);
    if (!await src.exists()) return;

    final dest = Directory(destPath);
    if (await dest.exists()) {
      final destFiles =
          await dest.list(recursive: true).whereType<File>().toList();
      if (destFiles.isNotEmpty) return; // already migrated
    }

    await dest.create(recursive: true);

    await for (final entity in src.list(recursive: true)) {
      if (entity is! File) continue;
      final relativePath = p.relative(entity.path, from: srcPath);
      final destFile = File(p.join(destPath, relativePath));
      await destFile.parent.create(recursive: true);
      try {
        await entity.copy(destFile.path);
        await entity.delete();
      } catch (e) {
        debugPrint('AppDirectories: migration failed for ${entity.path}: $e');
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<Directory> _ensure(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
