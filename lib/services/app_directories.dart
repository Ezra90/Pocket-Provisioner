import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

/// Centralised directory resolution for all Pocket Provisioner file stores.
///
/// All user-facing content (ringtones, wallpapers, phonebook, firmware) lives
/// in one self-contained folder at the root of Android external storage:
///
///   /storage/emulated/0/Pocket Provisioner/
///     firmware/          ← served at  /firmware/<file>
///     media/             ← served at  /media/<file>
///     phonebook/         ← served at  /phonebook/<file>
///     ringtones/         ← served at  /ringtones/<file>
///
/// The directory layout is intentionally identical to the provisioning server's
/// URL paths so files dropped via any Android file manager app are immediately
/// served without any extra steps.
///
/// **Permission strategy**
/// • Android 6–9  (API 23-28): `WRITE_EXTERNAL_STORAGE` — declared in the
///   manifest; requested at runtime via [ensureStoragePermission].
/// • Android 10   (API 29)   : same, plus `requestLegacyExternalStorage=true`
///   in the manifest for legacy broad access.
/// • Android 11+  (API 30+)  : `MANAGE_EXTERNAL_STORAGE` — opens the system
///   "All files access" settings screen when not yet granted.
///
/// If permission is denied the implementation falls back to the app-specific
/// external path (`Android/data/<pkg>/files/Pocket Provisioner/`), which still
/// uses the same named subfolder and is accessible without special permissions.
class AppDirectories {
  // ── Folder name ───────────────────────────────────────────────────────────

  static const String _folderName = 'Pocket Provisioner';

  // ── Base-directory cache ──────────────────────────────────────────────────

  /// Cleared by [resetCache] so tests and permission re-checks work correctly.
  static Future<Directory>? _userBaseFuture;

  /// Call after a permission change to force re-resolution of the base path.
  static void resetCache() => _userBaseFuture = null;

  // ── Base directory resolution ─────────────────────────────────────────────

  static Future<Directory> _internalBase() =>
      getApplicationDocumentsDirectory();

  /// Returns the app-specific external storage directory, or null if external
  /// storage is unavailable on this device.
  static Future<Directory?> _appSpecificExternal() async {
    if (!Platform.isAndroid) return null;
    try {
      return await getExternalStorageDirectory();
    } catch (_) {
      return null;
    }
  }

  /// Derives the external storage volume root from the app-specific external
  /// path.  On a typical device the app-specific path looks like:
  ///   /storage/emulated/0/Android/data/com.example.pocket_provisioner/files
  /// Splitting on '/Android/data/' gives us '/storage/emulated/0'.
  static Future<String?> _externalStorageRoot() async {
    final appExt = await _appSpecificExternal();
    if (appExt == null) return null;
    final parts = appExt.path.split('/Android/data/');
    if (parts.length < 2) return null;
    return parts.first; // e.g. /storage/emulated/0
  }

  /// Resolves (and caches) the base directory for all user-facing stores.
  ///
  /// Resolution order:
  ///   1. `/storage/emulated/0/Pocket Provisioner/`      — broad permission OK
  ///   2. `<appSpecificExternal>/Pocket Provisioner/`    — no permission needed
  ///   3. `<internalDocuments>/`                         — last resort
  static Future<Directory> _userBase() {
    return _userBaseFuture ??= _resolveUserBase();
  }

  static Future<Directory> _resolveUserBase() async {
    if (!Platform.isAndroid) return _internalBase();

    // ── Attempt 1: external storage root → Pocket Provisioner/ ──────────────
    final root = await _externalStorageRoot();
    if (root != null) {
      final ppDir = Directory(p.join(root, _folderName));
      try {
        if (!await ppDir.exists()) await ppDir.create(recursive: true);
        // Verify we can actually write there (permissions may be cached as
        // granted in the manifest but still blocked at runtime on API 30+).
        final testFile = File(p.join(ppDir.path, '.write_test'));
        await testFile.writeAsString('ok');
        await testFile.delete();
        return ppDir;
      } catch (_) {
        // Broad storage access denied — fall through to app-specific path.
      }
    }

    // ── Attempt 2: app-specific external → Pocket Provisioner/ ──────────────
    final appExt = await _appSpecificExternal();
    if (appExt != null) {
      final ppDir = Directory(p.join(appExt.path, _folderName));
      if (!await ppDir.exists()) await ppDir.create(recursive: true);
      return ppDir;
    }

    // ── Fallback: internal storage ────────────────────────────────────────────
    return _internalBase();
  }

  // ── Permission helper ─────────────────────────────────────────────────────

  /// Requests the storage permission appropriate for the running Android
  /// version.  Should be called once from the UI (e.g. inside
  /// `_checkPermissions`) so the system dialog or settings screen is shown in
  /// context.
  ///
  /// Returns `true` if broad external-storage access was granted.
  /// On non-Android platforms this always returns `false` (not applicable).
  static Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return false;

    // Android 11+ (API 30+) requires MANAGE_EXTERNAL_STORAGE for write access
    // outside the app-specific sandboxed directories.
    if (await Permission.manageExternalStorage.isGranted) {
      resetCache(); // re-resolve now that we have broad access
      return true;
    }

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      resetCache();
      return true;
    }

    // Fall back: request legacy WRITE_EXTERNAL_STORAGE for API 23-29.
    // On API 30+ this permission is a no-op but does no harm.
    final legacyStatus = await Permission.storage.request();
    if (legacyStatus.isGranted) {
      resetCache();
      return true;
    }

    return false;
  }

  // ── Named directories (mirrors web-server URL paths) ─────────────────────

  /// `Pocket Provisioner/firmware/` — served at `/firmware/<file>`
  static Future<Directory> firmwareDir() async =>
      _ensure(p.join((await _userBase()).path, 'firmware'));

  /// `Pocket Provisioner/ringtones/` — served at `/ringtones/<file>`
  static Future<Directory> ringtoneDir() async =>
      _ensure(p.join((await _userBase()).path, 'ringtones'));

  /// `Pocket Provisioner/ringtones/original/` — cached pre-conversion sources
  static Future<Directory> ringtoneOriginalDir() async =>
      _ensure(p.join((await _userBase()).path, 'ringtones', 'original'));

  /// `Pocket Provisioner/media/` — served at `/media/<file>`
  static Future<Directory> mediaDir() async =>
      _ensure(p.join((await _userBase()).path, 'media'));

  /// `Pocket Provisioner/media/original/` — cached pre-resize sources
  static Future<Directory> mediaOriginalDir() async =>
      _ensure(p.join((await _userBase()).path, 'media', 'original'));

  /// `Pocket Provisioner/phonebook/` — served at `/phonebook/<file>`
  static Future<Directory> phonebookDir() async =>
      _ensure(p.join((await _userBase()).path, 'phonebook'));

  // ── Internal-only directories (not user-editable) ────────────────────────

  /// Auto-generated MAC config files — not intended for manual editing.
  static Future<Directory> configsDir() async =>
      _ensure(p.join((await _internalBase()).path, 'generated_configs'));

  /// Custom Mustache provisioning templates.
  static Future<Directory> templatesDir() async =>
      _ensure(p.join((await _internalBase()).path, 'custom_templates'));

  // ── Migration ─────────────────────────────────────────────────────────────

  /// One-time migration of existing files to the canonical
  /// `Pocket Provisioner/` location.  Safe to call on every startup — skips
  /// any destination that already contains files.
  ///
  /// Migrates from two possible legacy locations:
  ///   • `<internalDocuments>/<subdir>/`        — original internal storage
  ///   • `<appSpecificExternal>/<subdir>/`      — intermediate app-external
  static Future<void> migrateToExternal() async {
    if (!Platform.isAndroid) return;

    final target = await _userBase();
    final internal = await _internalBase();
    final appExt = await _appSpecificExternal();

    const subdirs = ['firmware', 'ringtones', 'media', 'phonebook'];

    for (final sub in subdirs) {
      final dest = p.join(target.path, sub);

      // From legacy internal storage
      await _migrateDirectory(p.join(internal.path, sub), dest);

      // From intermediate app-specific external (if different from target)
      if (appExt != null) {
        final oldExt = p.join(appExt.path, sub);
        if (oldExt != dest) await _migrateDirectory(oldExt, dest);

        // Also handle the previous PR's "Pocket Provisioner" subfolder inside
        // app-specific external (if it was ever written there).
        if (appExt.path != target.path) {
          await _migrateDirectory(
              p.join(appExt.path, _folderName, sub), dest);
        }
      }
    }
  }

  /// Copies every file under [srcPath] to [destPath], preserving sub-directory
  /// structure, then deletes the source files.
  ///
  /// Skips silently when:
  ///   • [srcPath] does not exist
  ///   • [destPath] already contains at least one file (already migrated)
  static Future<void> _migrateDirectory(
      String srcPath, String destPath) async {
    if (srcPath == destPath) return;
    final src = Directory(srcPath);
    if (!await src.exists()) return;

    final dest = Directory(destPath);
    if (await dest.exists()) {
      final existing =
          await dest.list(recursive: true).whereType<File>().first.then(
                (_) => true,
                onError: (_) => false,
              );
      if (existing) return; // already has files — skip migration
    }

    await dest.create(recursive: true);

    await for (final entity in src.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: srcPath);
      final destFile = File(p.join(destPath, rel));
      await destFile.parent.create(recursive: true);
      try {
        await entity.copy(destFile.path);
        await entity.delete();
      } catch (e) {
        debugPrint('AppDirectories: migration skipped ${entity.path}: $e');
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
