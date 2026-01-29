import '../data/database_helper.dart';

class WallpaperSpec {
  final int width;
  final int height;
  final String format; // 'png' or 'jpg'
  final String label;

  const WallpaperSpec(this.width, this.height, this.label, {this.format = 'png'});
}

class DeviceTemplates {
  
  static const String defaultTarget = "http://polydms.digitalbusiness.telstra.com/dms/bootstrap";

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

  // --- TEMPLATE 1: YEALINK GENERIC (.cfg) ---
  static const String yealinkGeneric = '''
#!version:1.0.0.1
## Pocket Provisioner Config ##

# 1. ACCOUNT
account.1.enable = 1
account.1.label = {{label}}
account.1.display_name = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
# SIP SERVER: Injected from Settings (Real PBX IP) or Defaults to Android IP (Temp)
account.1.sip_server.1.address = {{sip_server_url}}
account.1.sip_server.1.port = 5060

# 2. LOCAL ASSETS
phone_setting.backgrounds = {{wallpaper_url}}

# 3. KEYS
{{dss_keys}}

# 4. SERVER HOP
static.auto_provision.server.url = {{target_url}}
static.auto_provision.server.username = {{extension}}
static.auto_provision.server.password = {{secret}}
static.auto_provision.enable = 1
static.auto_provision.power_on = 1
static.auto_provision.custom.protect = 0
static.auto_provision.reboot_force.enable = 1
features.show_quick_setup.enable = 0
''';

  // --- TEMPLATE 2: POLYCOM (.xml) ---
  static const String polycomGeneric = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PHONE_CONFIG>
  <REGISTRATION
    reg.1.displayName="{{label}}"
    reg.1.address="{{extension}}"
    reg.1.auth.userId="{{extension}}"
    reg.1.auth.password="{{secret}}"
    reg.1.server.1.address="{{sip_server_url}}"
    reg.1.server.1.port="5060"
  />
  <bg>
    <bg.color>
      <bg.color.bm bg.color.bm.1.name="{{wallpaper_url}}" />
    </bg.color>
  </bg>
  <DEVICE 
    device.prov.serverName="{{target_url}}"
    device.prov.user="{{extension}}"
    device.prov.password="{{secret}}"
    device.prov.serverType="HTTP"
  />
</PHONE_CONFIG>
''';

  // --- TEMPLATE 3: CISCO (.xml) ---
  static const String ciscoGeneric = '''
<?xml version="1.0" encoding="UTF-8"?>
<device>
    <deviceProtocol>SIP</deviceProtocol>
    <sipProfile>
        <sipProxies>
            <registerWithProxy>true</registerWithProxy>
            <proxy1_address>{{sip_server_url}}</proxy1_address>
            <proxy1_port>5060</proxy1_port>
        </sipProxies>
        <sipLines>
            <line button="1">
                <featureID>9</featureID>
                <featureLabel>{{label}}</featureLabel>
                <name>{{extension}}</name>
                <displayName>{{label}}</displayName>
                <authName>{{extension}}</authName>
                <authPassword>{{secret}}</authPassword>
            </line>
        </sipLines>
    </sipProfile>
    <userLocale>
        <backgroundFile>{{wallpaper_url}}</backgroundFile>
    </userLocale>
    <provisioning>
        <profile_rule>{{target_url}}/$MA.xml</profile_rule>
    </provisioning>
</device>
''';

  static Future<String> getTemplateForModel(String model) async {
    final normalized = model.trim().toUpperCase();
    
    // Check Database
    final custom = await DatabaseHelper.instance.getTemplate(normalized);
    if (custom != null) return custom['content'] as String;

    if (normalized.contains('CISCO') || normalized.contains('88') || normalized.contains('78')) {
      return ciscoGeneric;
    } else if (normalized.contains('POLY') || normalized.contains('VVX') || normalized.contains('EDGE')) {
      return polycomGeneric;
    }
    return yealinkGeneric;
  }
  
  static Future<String> getContentType(String model) async {
    final normalized = model.trim().toUpperCase();
    final custom = await DatabaseHelper.instance.getTemplate(normalized);
    if (custom != null) return custom['content_type'] as String;

    if (normalized.contains('POLY') || normalized.contains('VVX') || normalized.contains('CISCO') || normalized.contains('EDGE')) {
      return 'application/xml';
    }
    return 'text/plain';
  }
}
