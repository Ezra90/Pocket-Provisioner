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
/// [isTouchscreen] – true for touchscreen models (T48G, T57W, VVX1500, etc.).
/// [isLandscape]  – true for landscape-oriented models (VVX1500).
/// [maxKeys]      – manufacturer max programmable keys (0 = use leftKeyCount+rightKeyCount).
/// [initialVisibleKeys] – keys visible before "More" is pressed (0 = maxKeys).
/// [keyPages]     – number of pages for physical-key models (e.g. 3 for T54W).
/// [expandButtonLabel]   – label shown on the expand button (e.g. '+ Show More').
/// [collapseButtonLabel] – label shown on the collapse button (e.g. '— Show Less').
/// [softKeyLabels]       – bottom bar button labels.
/// [softKeysAreCustomizable] – whether the bottom soft keys can be edited.
class PhysicalLayout {
  final int leftKeyCount;
  final int rightKeyCount;
  final bool hasSoftKeys;
  final bool hasNavCluster;
  final bool hasDialPad;
  final int bodyColorValue;
  final String modelFamily;

  // Touchscreen / orientation
  final bool isTouchscreen;
  final bool isLandscape;

  // Key counts and pagination
  final int maxKeys;             // 0 → use leftKeyCount + rightKeyCount
  final int initialVisibleKeys;  // 0 → use totalKeyCount
  final int keyPages;

  // Expand / collapse labels
  final String expandButtonLabel;
  final String collapseButtonLabel;

  // Bottom bar
  final List<String> softKeyLabels;
  final bool softKeysAreCustomizable;

  const PhysicalLayout({
    required this.leftKeyCount,
    required this.rightKeyCount,
    this.hasSoftKeys = true,
    this.hasNavCluster = true,
    this.hasDialPad = true,
    this.bodyColorValue = 0xFF424242, // Colors.grey[800]
    required this.modelFamily,
    this.isTouchscreen = false,
    this.isLandscape = false,
    this.maxKeys = 0,
    this.initialVisibleKeys = 0,
    this.keyPages = 1,
    this.expandButtonLabel = '',
    this.collapseButtonLabel = '',
    this.softKeyLabels = const <String>[],
    this.softKeysAreCustomizable = false,
  });

  /// Effective total programmable key count.
  int get totalKeyCount => maxKeys > 0 ? maxKeys : leftKeyCount + rightKeyCount;

  /// Keys visible per page (or default/collapsed view).
  int get keysPerPage => leftKeyCount + rightKeyCount;
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
    'Yealink T48G / T57W': WallpaperSpec(800, 480, 'Large Color Display'),
    'Yealink T58W':        WallpaperSpec(1024, 600, 'Flagship Video Phone'),
    'Poly VVX 150-350':    WallpaperSpec(320, 240, 'VVX Compact'),
    'Poly VVX 450':        WallpaperSpec(480, 272, 'VVX Full'),
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

  // ── Family fallback layouts ──────────────────────────────────────────────

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

  // ── Per-model exact layouts ──────────────────────────────────────────────
  //
  // Keys are looked up by uppercase model string before falling back to the
  // family layouts above.

  static const Map<String, PhysicalLayout> _modelLayouts = {

    // ── Yealink physical-key models ─────────────────────────────────────────

    // T54W / T46U: 27 max keys across 3 pages of 10 (last page has 7)
    'T54W': PhysicalLayout(
      leftKeyCount: 5, rightKeyCount: 5,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF37474F,
      modelFamily: 'Yealink T4x/T5x',
      maxKeys: 27, keyPages: 3,
    ),
    'T46U': PhysicalLayout(
      leftKeyCount: 5, rightKeyCount: 5,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF37474F,
      modelFamily: 'Yealink T4x/T5x',
      maxKeys: 27, keyPages: 3,
    ),

    // ── Yealink touchscreen models ───────────────────────────────────────────

    // T48G: 7" color touchscreen (800x480), 29 virtual DSS keys displayed in
    // a grid pattern. Keys 1-6 shown on left, 7-11 on right initially, then
    // expand to show all 29 in a 4-5 column grid via touchscreen navigation.
    'T48G': PhysicalLayout(
      leftKeyCount: 6, rightKeyCount: 5,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF37474F,
      modelFamily: 'Yealink T4x/T5x',
      isTouchscreen: true,
      maxKeys: 29, initialVisibleKeys: 11,
      expandButtonLabel: '+ Show More',
      collapseButtonLabel: '— Show Less',
      softKeyLabels: <String>['Directory', 'UnPark', 'GPickup', 'Menu'],
      softKeysAreCustomizable: true,
    ),
    // T57W: 7" color LCD (800x480) - NOT a touchscreen! Has 10 physical line keys
    // (5 left + 5 right) around the display, pageable to 27 total across 3 pages.
    'T57W': PhysicalLayout(
      leftKeyCount: 5, rightKeyCount: 5,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF37474F,
      modelFamily: 'Yealink T4x/T5x',
      isTouchscreen: false,  // T57W has a non-touch LCD display
      maxKeys: 27, keyPages: 3,
    ),
    // T58W: 7" color capacitive touchscreen (1024x600), 27 virtual DSS keys
    // arranged on the touchscreen. Supports swipe navigation between 3 pages.
    'T58W': PhysicalLayout(
      leftKeyCount: 6, rightKeyCount: 5,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF37474F,
      modelFamily: 'Yealink T4x/T5x',
      isTouchscreen: true,
      maxKeys: 27, initialVisibleKeys: 11,
      expandButtonLabel: '+ Show More',
      collapseButtonLabel: '— Show Less',
      softKeyLabels: <String>['Directory', 'UnPark', 'GPickup', 'Menu'],
      softKeysAreCustomizable: true,
    ),
    // T58G: 7" color capacitive touchscreen (800x480), similar to T48G but
    // video capable. 27 virtual DSS keys arranged on the touchscreen.
    'T58G': PhysicalLayout(
      leftKeyCount: 6, rightKeyCount: 5,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF37474F,
      modelFamily: 'Yealink T4x/T5x',
      isTouchscreen: true,
      maxKeys: 27, initialVisibleKeys: 11,
      expandButtonLabel: '+ Show More',
      collapseButtonLabel: '— Show Less',
      softKeyLabels: <String>['Directory', 'UnPark', 'GPickup', 'Menu'],
      softKeysAreCustomizable: true,
    ),

    // ── Polycom VVX physical models ──────────────────────────────────────────

    // VVX150: 2 line keys (1 left + 1 right), 2.5" monochrome LCD
    'VVX150': PhysicalLayout(
      leftKeyCount: 1, rightKeyCount: 1,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF4A148C,
      modelFamily: 'Polycom VVX / Poly Edge',
      maxKeys: 2,
    ),
    // VVX250: 4 line keys (2 left + 2 right), 2.8" color LCD (320x240)
    'VVX250': PhysicalLayout(
      leftKeyCount: 2, rightKeyCount: 2,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF4A148C,
      modelFamily: 'Polycom VVX / Poly Edge',
      maxKeys: 4,
    ),
    // VVX350: 6 line keys (3 left + 3 right), 3.5" color LCD (320x240)
    'VVX350': PhysicalLayout(
      leftKeyCount: 3, rightKeyCount: 3,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF4A148C,
      modelFamily: 'Polycom VVX / Poly Edge',
      maxKeys: 6,
    ),
    // VVX450: 12 line keys (6 left + 6 right), 4.3" color LCD (480x272)
    'VVX450': PhysicalLayout(
      leftKeyCount: 6, rightKeyCount: 6,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF4A148C,
      modelFamily: 'Polycom VVX / Poly Edge',
      maxKeys: 12,
    ),

    // ── Polycom VVX1500 landscape touchscreen ────────────────────────────────
    // 7" TFT LCD touchscreen (800x480, 16:9), resistive touch
    // Line keys shown on right side of screen, up to 6 visible, 24 total with overlay
    'VVX1500': PhysicalLayout(
      leftKeyCount: 0, rightKeyCount: 6,
      hasSoftKeys: true, hasNavCluster: false, hasDialPad: false,
      bodyColorValue: 0xFF212121,
      modelFamily: 'Polycom VVX / Poly Edge',
      isTouchscreen: true, isLandscape: true,
      maxKeys: 24, initialVisibleKeys: 6,
      expandButtonLabel: 'More',
      collapseButtonLabel: 'Close',
      softKeyLabels: <String>['New Call', 'Forward', 'MyStat', 'Buddies'],
    ),

    // ── Poly Edge physical models ────────────────────────────────────────────

    // Edge E350: 8 line keys (4 left + 4 right), pageable to 32 total (4 pages)
    // 3.5" color LCD (320x240)
    'EDGE E350': PhysicalLayout(
      leftKeyCount: 4, rightKeyCount: 4,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF4A148C,
      modelFamily: 'Polycom VVX / Poly Edge',
      maxKeys: 32, keyPages: 4,
    ),
    // Edge E450: 14 line keys (8 main + 6 secondary display), pageable
    // Main: 3.5" LCD (320x240), Secondary: 2.4" LCD (240x320)
    'EDGE E450': PhysicalLayout(
      leftKeyCount: 4, rightKeyCount: 4,  // Main display keys per page
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF4A148C,
      modelFamily: 'Polycom VVX / Poly Edge',
      maxKeys: 44, keyPages: 4,  // 32 main + 12 secondary
    ),

    // ── Cisco physical models ────────────────────────────────────────────────

    // Cisco 8851: 5" color LCD (800x480), 5 physical programmable line keys
    // on the LEFT side only. Keys are pageable to 10 total across 2 pages.
    // Right side has session buttons (not programmable for features).
    'CISCO 8851': PhysicalLayout(
      leftKeyCount: 5, rightKeyCount: 0,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF1A237E,
      modelFamily: 'Cisco 78xx/88xx',
      maxKeys: 10, keyPages: 2, initialVisibleKeys: 5,
    ),
    // Cisco 8865: Same as 8851 but with video camera. 5" color LCD (800x480),
    // 5 physical programmable line keys on left, pageable to 10 across 2 pages.
    'CISCO 8865': PhysicalLayout(
      leftKeyCount: 5, rightKeyCount: 0,
      hasSoftKeys: true, hasNavCluster: true, hasDialPad: true,
      bodyColorValue: 0xFF1A237E,
      modelFamily: 'Cisco 78xx/88xx',
      maxKeys: 10, keyPages: 2, initialVisibleKeys: 5,
    ),
  };

  /// Returns the [PhysicalLayout] for [model].
  ///
  /// First tries an exact model-string match (case-insensitive) from
  /// [_modelLayouts], then falls back to brand-family detection.
  static PhysicalLayout getPhysicalLayout(String model) {
    final upper = model.toUpperCase().trim();
    if (upper.isEmpty) return _yealinkLayout;

    // Exact per-model lookup.
    final exact = _modelLayouts[upper];
    if (exact != null) return exact;

    // Brand-family fallback.
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

  /// Returns the [wallpaperSpecs] display-name key that best matches [model].
  /// Used to pre-select the correct entry in the wallpaper spec dropdown.
  static String getWallpaperSpecKeyForDeviceModel(String model) {
    final upper = model.toUpperCase().trim();
    if (upper == 'T54W' || upper == 'T46U') return 'Yealink T54W / T46U';
    if (upper == 'T48G' || upper == 'T57W') return 'Yealink T48G / T57W';
    if (upper == 'T58W') return 'Yealink T58W';
    if (upper == 'T58G') return 'Yealink T48G / T57W';
    if (upper == 'VVX450') return 'Poly VVX 450';
    if (upper == 'VVX150' || upper == 'VVX250' || upper == 'VVX350') {
      return 'Poly VVX 150-350';
    }
    if (upper == 'VVX1500') return 'Poly VVX 1500';
    if (upper == 'EDGE E450') return 'Poly Edge E450';
    if (upper == 'EDGE E350') return 'Poly Edge E350';
    if (upper.contains('CISCO') ||
        upper.contains('8851') ||
        upper.contains('8865')) return 'Cisco 8851 / 8865';
    return wallpaperSpecs.keys.first;
  }

  /// Returns the [WallpaperSpec] that best matches [model].
  static WallpaperSpec getWallpaperSpecForDeviceModel(String model) =>
      getSpecForModel(getWallpaperSpecKeyForDeviceModel(model));

  static WallpaperSpec getSpecForModel(String modelKey) {
    return wallpaperSpecs[modelKey] ?? const WallpaperSpec(480, 272, 'Default');
  }
}
