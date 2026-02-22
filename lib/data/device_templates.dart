class WallpaperSpec {
  final int width;
  final int height;
  final String format; // 'png' or 'jpg'
  final String label;

  const WallpaperSpec(this.width, this.height, this.label, {this.format = 'png'});
}

class RingtoneSpec {
  final String format;
  final int sampleRate;
  final int bitDepth;
  final String channels;
  final int maxSizeBytes;
  const RingtoneSpec(this.format, this.sampleRate, this.bitDepth, this.channels, this.maxSizeBytes);
}

/// Describes the physical programmable-key layout of a handset family.
///
/// Keys are split into a [leftKeyCount] left column alongside the screen
/// and a [rightKeyCount] right column.  Left keys occupy IDs 1…leftKeyCount,
/// right keys occupy IDs leftKeyCount+1…totalKeyCount.
///
/// [hasSoftKeys]  – true if the model has 4 soft-key buttons below the screen.
/// [hasNavCluster] – true if the model has a 5-way navigation cluster.
/// [hasDialPad]   – true if the model has a full 12-key dial pad.
/// [bodyColor]    – base colour used to paint the phone body.
/// [screenRatio]  – fraction of the centre column width taken by the screen
///                  (0.0 = no screen shown, 1.0 = full width).
class PhysicalLayout {
  final int leftKeyCount;
  final int rightKeyCount;
  final bool hasSoftKeys;
  final bool hasNavCluster;
  final bool hasDialPad;
  final int bodyColorValue;
  final String modelFamily;

  const PhysicalLayout({
    required this.leftKeyCount,
    required this.rightKeyCount,
    this.hasSoftKeys = true,
    this.hasNavCluster = true,
    this.hasDialPad = true,
    this.bodyColorValue = 0xFF424242, // Colors.grey[800]
    required this.modelFamily,
  });

  int get totalKeyCount => leftKeyCount + rightKeyCount;
}

class DeviceTemplates {
  
  static const String defaultTarget = "";

  /// Comprehensive list of supported handset models shown in pickers.
  static const List<String> supportedModels = [
    'T54W', 'T46U', 'T48G', 'T57W', 'T58W', 'T58G',
    'VVX150', 'VVX250', 'VVX350', 'VVX450', 'VVX1500',
    'Edge E350', 'Edge E450',
    'Cisco 8851', 'Cisco 8865',
  ];

  // --- WALLPAPER DATABASE ---
  static const Map<String, WallpaperSpec> wallpaperSpecs = {
    'Yealink T54W / T46U': WallpaperSpec(480, 272, 'Standard Color Screen'),
    'Yealink T48G / T57W': WallpaperSpec(800, 480, 'Touch Screen Large'),
    'Yealink T58W':        WallpaperSpec(1024, 600, 'Flagship Video Phone'),
    'Poly Edge E450':      WallpaperSpec(480, 272, 'Edge Series Mid'),
    'Poly Edge E350':      WallpaperSpec(320, 240, 'Edge Series Compact'),
    'Poly VVX 1500':       WallpaperSpec(800, 480, 'Legacy Video'),
    'Cisco 8851 / 8865':   WallpaperSpec(800, 480, 'Cisco High Res'),
  };

  /// Default ringtone filename used by all vendors when no custom ringtone
  /// is configured.  Referenced in [MustacheRenderer.buildVariables] and the
  /// ringtone dropdown hint text.
  static const String defaultRingtoneName = 'Ring1.wav';
  static const RingtoneSpec ringtoneSpec = RingtoneSpec(
    'WAV (PCM)', 8000, 16, 'Mono', 1048576,
  );

  // --- PHYSICAL BUTTON LAYOUT DATABASE ---
  // Defines the left/right key column arrangement for each handset family.
  // Yealink T4x/T5x: 5 keys on each side of the screen (10 total)
  static const PhysicalLayout _yealinkLayout = PhysicalLayout(
    leftKeyCount: 5,
    rightKeyCount: 5,
    hasSoftKeys: true,
    hasNavCluster: true,
    hasDialPad: true,
    bodyColorValue: 0xFF37474F, // blue-grey
    modelFamily: 'Yealink T4x/T5x',
  );

  // Cisco 88xx: 5 keys on each side (10 total)
  static const PhysicalLayout _ciscoLayout = PhysicalLayout(
    leftKeyCount: 5,
    rightKeyCount: 5,
    hasSoftKeys: true,
    hasNavCluster: true,
    hasDialPad: true,
    bodyColorValue: 0xFF1A237E, // dark navy
    modelFamily: 'Cisco 78xx/88xx',
  );

  // Polycom VVX: 6 keys on each side (12 total, covers VVX450 — smaller models
  // use fewer but the editor gracefully handles empty slots)
  static const PhysicalLayout _polycomLayout = PhysicalLayout(
    leftKeyCount: 6,
    rightKeyCount: 6,
    hasSoftKeys: true,
    hasNavCluster: true,
    hasDialPad: true,
    bodyColorValue: 0xFF4A148C, // deep purple
    modelFamily: 'Polycom VVX / Poly Edge',
  );

  /// Returns the [PhysicalLayout] for [model], falling back to Yealink style.
  static PhysicalLayout getPhysicalLayout(String model) {
    final upper = model.toUpperCase();
    // Cisco: explicit brand name OR 4-digit model numbers starting with 78xx/88xx
    if (upper.contains('CISCO') ||
        RegExp(r'(?:^|[^0-9])(?:78|88)\d{2}').hasMatch(upper)) {
      return _ciscoLayout;
    }
    if (upper.contains('POLY') ||
        upper.contains('VVX') ||
        upper.contains('EDGE')) {
      return _polycomLayout;
    }
    return _yealinkLayout;
  }

  static WallpaperSpec getSpecForModel(String modelKey) {
    return wallpaperSpecs[modelKey] ?? const WallpaperSpec(480, 272, 'Default');
  }
}
