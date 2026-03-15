import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import 'build_info.dart';

/// Describes an available update fetched from GitHub Releases.
class UpdateInfo {
  final String version;
  final String tagName;
  final String downloadUrl;
  final String assetName;
  final String releaseNotes;
  final int buildNumber;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.assetName,
    required this.releaseNotes,
    this.buildNumber = 0,
  });
}

/// Status information about the current vs latest build.
class UpdateStatus {
  final int currentBuild;
  final int? latestBuild;
  final bool updateAvailable;
  final String? error;
  final String? currentSha;
  final String? latestSha;

  const UpdateStatus({
    required this.currentBuild,
    required this.latestBuild,
    this.updateAvailable = false,
    this.error,
    this.currentSha,
    this.latestSha,
  });

  String get message {
    if (error != null) return error!;
    if (latestBuild == null) return 'Could not determine latest version';
    if (updateAvailable) return 'Update available: Build $latestBuild';
    return 'You have the latest version (Build $latestBuild)';
  }
}

/// Service that checks the GitHub Releases API for a newer version of the app
/// and, if one exists, downloads and installs it.
///
/// Version tracking uses the commit SHA as the primary identifier for CI builds.
/// The build workflow creates a rolling "dev" pre-release on every push to main
/// with raw APK assets attached, so the app can self-update without manual
/// tagging. For local/dev builds without a commit SHA, it falls back to
/// comparing build numbers (git commit count).
class UpdateService {
  static const String _repoOwner = 'Ezra90';
  static const String _repoName = 'Pocket-Provisioner';

  /// Matches a short commit SHA in parentheses, e.g. "(a016a6e)" in "Build 346 (a016a6e)".
  static final RegExp _shaPattern = RegExp(r'\(([a-f0-9]{7,})\)');

  /// Returns [UpdateInfo] if a newer release is available, otherwise null.
  ///
  /// Checks the rolling "dev" release first (created by the build workflow on
  /// every push to main), then falls back to recent tagged releases.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 1. Check the rolling "dev" pre-release first (most common update path).
      final devUpdate = await _checkRelease(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/tags/dev',
        currentBuild,
      );
      if (devUpdate != null) return devUpdate;

      // 2. Fall back to the latest non-prerelease (tagged releases like v1.0.0).
      return _checkRelease(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
        currentBuild,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns detailed update status for debugging/display purposes.
  /// 
  /// Unlike [checkForUpdate], this returns info even when already on the latest
  /// version, so users can see their current build vs the latest available.
  /// For CI builds, uses commit SHA comparison instead of build numbers to
  /// avoid false results after git history rewrites.
  static Future<UpdateStatus> getUpdateStatus() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentSha = BuildInfo.commitSha;

      // Check the dev release
      final response = await http
          .get(Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/tags/dev'),
              headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return UpdateStatus(
          currentBuild: currentBuild,
          latestBuild: null,
          error: 'Could not reach update server (${response.statusCode})',
          currentSha: currentSha,
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final releaseName = data['name'] as String? ?? '';
      final buildMatch = RegExp(r'Build\s+(\d+)').firstMatch(releaseName);
      
      if (buildMatch == null) {
        return UpdateStatus(
          currentBuild: currentBuild,
          latestBuild: null,
          error: 'Could not parse release version from "$releaseName"',
          currentSha: currentSha,
        );
      }

      final latestBuild = int.tryParse(buildMatch.group(1)!) ?? 0;

      // Extract commit SHA from release name (format: "Build N (abc1234)")
      final shaMatch = _shaPattern.firstMatch(releaseName);
      final latestSha = shaMatch?.group(1);

      // Determine if an update is available:
      // - For CI builds with SHA info: compare commit SHAs (immune to history rewrites)
      // - For local/dev builds: fall back to build number comparison
      final bool isUpdate;
      if (BuildInfo.isCiBuild && latestSha != null) {
        isUpdate = currentSha != latestSha;
      } else {
        isUpdate = latestBuild > currentBuild;
      }
      
      return UpdateStatus(
        currentBuild: currentBuild,
        latestBuild: latestBuild,
        updateAvailable: isUpdate,
        currentSha: currentSha,
        latestSha: latestSha,
      );
    } catch (e) {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      return UpdateStatus(
        currentBuild: currentBuild,
        latestBuild: null,
        error: 'Update check failed: $e',
        currentSha: BuildInfo.commitSha,
      );
    }
  }

  /// Checks a single release endpoint for a newer build.
  /// For CI builds, uses commit SHA comparison to avoid false results after
  /// git history rewrites. Falls back to build number comparison for local builds.
  static Future<UpdateInfo?> _checkRelease(String url, int currentBuild) async {
    try {
      final response = await http
          .get(Uri.parse(url),
              headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final releaseName = data['name'] as String? ?? '';
      final tagName = data['tag_name'] as String? ?? '';

      // Extract build number from release name "Build N (abc1234)" or
      // "Pocket-Provisioner vX.Y.Z (Build N)".
      final buildMatch = RegExp(r'Build\s+(\d+)').firstMatch(releaseName);
      if (buildMatch == null) return null;

      final releaseBuild = int.tryParse(buildMatch.group(1)!) ?? 0;

      // Determine if this release is newer than the current build:
      // - For CI builds: compare commit SHAs (immune to git history rewrites)
      // - For local/dev builds: fall back to build number comparison
      if (BuildInfo.isCiBuild) {
        final shaMatch = _shaPattern.firstMatch(releaseName);
        final releaseSha = shaMatch?.group(1);
        if (releaseSha != null && releaseSha == BuildInfo.commitSha) return null;
        // SHAs differ (or couldn't extract SHA) – fall through to offer update
      } else {
        if (releaseBuild <= currentBuild) return null;
      }

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
        version: 'Build $releaseBuild',
        tagName: tagName,
        downloadUrl: downloadUrl,
        assetName: assetName,
        releaseNotes: (data['body'] as String? ?? '').trim(),
        buildNumber: releaseBuild,
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

      // Remove any stale or partial APK from a previous attempt.
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(info.downloadUrl));
        final streamedResponse = client.send(request);
        final response = await streamedResponse
            .timeout(const Duration(minutes: 10));

        // Verify successful response before attempting to download
        if (response.statusCode != 200) {
          onError('Download failed: Server returned ${response.statusCode}');
          return;
        }

        final contentLength = response.contentLength ?? 0;
        int downloaded = 0;

        final sink = apkFile.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            downloaded += chunk.length;
            if (contentLength > 0) {
              onProgress(downloaded / contentLength);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }

      // Verify the downloaded file is not empty
      final fileSize = await apkFile.length();
      if (fileSize == 0) {
        onError('Download failed: Empty file received');
        return;
      }

      final result = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        onError('Could not open installer: ${result.message}');
      }
    } on TimeoutException {
      onError('Download timed out. Please check your connection and try again.');
    } on SocketException catch (e) {
      onError('Network error: ${e.message}');
    } catch (e) {
      onError('Download failed: $e');
    }
  }
}
