class WallpaperSpec {
  final int width;
  final int height;
  final String format; // 'png' or 'jpg'
  final String label;

  const WallpaperSpec(this.width, this.height, this.label, {this.format = 'png'});
}

class DeviceTemplates {
  
  static const String defaultTarget = "";

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

  static WallpaperSpec getSpecForModel(String modelKey) {
    return wallpaperSpecs[modelKey] ?? const WallpaperSpec(480, 272, 'Default');
  }
}
