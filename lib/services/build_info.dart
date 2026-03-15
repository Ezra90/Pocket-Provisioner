/// Compile-time build metadata.
///
/// These values are set via `--dart-define` during CI builds. When building
/// locally without these defines, sensible defaults are used.
///
/// Usage:
/// ```bash
/// flutter build apk --dart-define=COMMIT_SHA=abc1234
/// ```
class BuildInfo {
  /// The short git commit SHA at build time (e.g., "abc1234").
  /// Returns "dev" for local builds without the define.
  static const String commitSha = String.fromEnvironment(
    'COMMIT_SHA',
    defaultValue: 'dev',
  );

  /// Whether this is a CI build (has commit SHA defined).
  static bool get isCiBuild => commitSha != 'dev';
}
