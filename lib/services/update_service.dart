import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Describes an available update fetched from GitHub Releases.
class UpdateInfo {
  final String version;
  final String tagName;
  final String downloadUrl;
  final String assetName;
  final String releaseNotes;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.assetName,
    required this.releaseNotes,
  });
}

/// Service that checks the GitHub Releases API for a newer version of the app
/// and, if one exists, downloads and installs it.
class UpdateService {
  static const String _repoOwner = 'Ezra90';
  static const String _repoName = 'Pocket-Provisioner';

  /// Returns [UpdateInfo] if a newer release is available, otherwise null.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "0.0.4"

      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').trim();
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      if (!_isNewerVersion(latestVersion, currentVersion)) return null;

      // Find the best APK asset: prefer arm64-v8a, fall back to any .apk.
      final assets = (data['assets'] as List<dynamic>? ?? []);
      String? downloadUrl;
      String? assetName;

      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '');
        if (!name.endsWith('.apk')) continue;
        if (name.contains('arm64')) {
          downloadUrl = asset['browser_download_url'] as String?;
          assetName = name;
          break;
        }
        downloadUrl ??= asset['browser_download_url'] as String?;
        assetName ??= name;
      }

      if (downloadUrl == null || assetName == null) return null;

      return UpdateInfo(
        version: latestVersion,
        tagName: tagName,
        downloadUrl: downloadUrl,
        assetName: assetName,
        releaseNotes: (data['body'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK from [info] and launches the Android package installer.
  ///
  /// [onProgress] is called with a value in [0.0, 1.0] as the download advances.
  /// [onError] is called with a message if something goes wrong.
  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress) onProgress,
    required void Function(String error) onError,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final apkPath = '${tempDir.path}/${info.assetName}';
      final apkFile = File(apkPath);

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        final streamedResponse = client.send(request);
        final response = await streamedResponse
            .timeout(const Duration(minutes: 10));

        final contentLength = response.contentLength ?? 0;
        int downloaded = 0;

        final sink = apkFile.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (contentLength > 0) {
            onProgress(downloaded / contentLength);
          }
        }
        await sink.flush();
        await sink.close();
      } finally {
        client.close();
      }

      final result = await OpenFilex.open(apkPath);
      if (result.type != ResultType.done) {
        onError('Could not open installer: ${result.message}');
      }
    } on SocketException catch (e) {
      onError('Network error: ${e.message}');
    } catch (e) {
      onError('Download failed: $e');
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// Returns true when [latest] is strictly greater than [current] using
  /// major.minor.patch comparison.
  static bool _isNewerVersion(String latest, String current) {
    final latestParts = _versionParts(latest);
    final currentParts = _versionParts(current);
    for (int i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static List<int> _versionParts(String version) =>
      version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
}
