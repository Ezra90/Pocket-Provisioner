import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_provisioner/services/update_service.dart';

void main() {
  group('UpdateStatus.message', () {
    test('shows error when error is set', () {
      const status = UpdateStatus(
        currentBuild: 100,
        latestBuild: null,
        error: 'Network failure',
      );
      expect(status.message, 'Network failure');
    });

    test('shows could not determine when latestBuild is null', () {
      const status = UpdateStatus(
        currentBuild: 100,
        latestBuild: null,
      );
      expect(status.message, 'Could not determine latest version');
    });

    test('shows update available when updateAvailable is true', () {
      const status = UpdateStatus(
        currentBuild: 100,
        latestBuild: 200,
        updateAvailable: true,
      );
      expect(status.message, 'Update available: Build 200');
    });

    test('shows latest version when builds match', () {
      const status = UpdateStatus(
        currentBuild: 100,
        latestBuild: 100,
      );
      expect(status.message, 'You have the latest version (Build 100)');
    });

    test('shows current build number even when release build differs (history rewrite)', () {
      // After a git history rewrite, the current build number (from
      // github.run_number) may differ from the release build number.
      // The message should use currentBuild so it matches the app bar.
      const status = UpdateStatus(
        currentBuild: 2343,
        latestBuild: 346,
        updateAvailable: false,
        currentSha: 'a016a6e',
        latestSha: 'a016a6e',
      );
      expect(status.message, 'You have the latest version (Build 2343)');
      expect(status.message, isNot(contains('newer build')));
    });

    test('shows update available when SHAs differ even with higher build number', () {
      // User has higher build number but different SHA — update IS available
      const status = UpdateStatus(
        currentBuild: 2343,
        latestBuild: 346,
        updateAvailable: true,
        currentSha: '26c3e28',
        latestSha: 'a016a6e',
      );
      expect(status.message, 'Update available: Build 346');
    });

    test('shows latest version for local dev builds at same build number', () {
      const status = UpdateStatus(
        currentBuild: 50,
        latestBuild: 50,
        updateAvailable: false,
        currentSha: 'dev',
      );
      expect(status.message, 'You have the latest version (Build 50)');
    });
  });
}
