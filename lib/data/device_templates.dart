import '../data/database_helper.dart';

class DeviceTemplates {
  static const String defaultTarget = "http://polydms.digitalbusiness.telstra.com/dms/bootstrap";

  /* WALLPAPER REFERENCE (WxH pixels):
    - Yealink T54W / T46U: 480x272
    - Yealink T48G / T57W: 800x480
    - Yealink T58W: 1024x600
    - Poly Edge E450: 480x272
    - Poly Edge E350: 320x240
    - Poly VVX 1500: 800x480
    - Cisco 8851 / 8865: 800x480
  */

  // ---------------------------------------------------------------------------
  // YEALINK TEMPLATE (.cfg)
  // Supports: T4x, T5x series
  // ---------------------------------------------------------------------------
  static const String fallbackYealinkTemplate = '''
#!version:1.0.0.1
## Pocket Provisioner Generated Config ##
## Model: {{model}} | Extension: {{extension}} | Label: {{label}} ##

# --- ACCOUNT 1 (Temp Local Reg) ---
account.1.enable = 1
account.1.label = {{label}}
account.1.display_name = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
account.1.sip_server.1.address = {{local_ip}}
account.1.sip_server.1.port = 5060

# --- WALLPAPER ---
phone_setting.backgrounds = {{wallpaper_url}}
# Ensure format matches device (T54W=480x272, T48=800x480)

# --- KEYS (Injected by Server) ---
{{dss_keys}}

# --- THE SERVER HOP (Auto-Provision to ISP) ---
static.auto_provision.server.url = {{target_url}}
static.auto_provision.enable = 1
static.auto_provision.repeat.enable = 1
static.auto_provision.power_on = 1
# Force reboot/update to trigger the move to production immediately
static.auto_provision.reboot_force.enable = 1
static.auto_provision.update_file_enable = 1
static.firmware.url = 
''';

  // ---------------------------------------------------------------------------
  // POLYCOM TEMPLATE (.xml)
  // Supports: VVX, Edge E Series
  // ---------------------------------------------------------------------------
  static const String fallbackPolycomTemplate = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PHONE_CONFIG>
  <REGISTRATION
    reg.1.displayName="{{label}}"
    reg.1.address="{{extension}}"
    reg.1.auth.userId="{{extension}}"
    reg.1.auth.password="{{secret}}"
    reg.1.server.1.address="{{local_ip}}"
  />
  
  <bg>
    <bg.color>
      <bg.color.bm bg.color.bm.1.name="{{wallpaper_url}}" />
    </bg.color>
  </bg>

  <DEVICE device.prov.serverName="{{target_url}}" 
          device.prov.serverType="HTTP"
          device.prov.tagSerialNo="1" />
</PHONE_CONFIG>
''';

  // ---------------------------------------------------------------------------
  // CISCO 3PCC TEMPLATE (.xml)
  // Supports: 8851, 8865 (3rd Party Call Control Firmware)
  // ---------------------------------------------------------------------------
  static const String fallbackCiscoTemplate = '''
<?xml version="1.0" encoding="UTF-8"?>
<device>
    <deviceProtocol>SIP</deviceProtocol>
    <sshUserId>admin</sshUserId>
    <sshPassword>cisco</sshPassword>
    
    <sipProfile>
        <sipProxies>
            <registerWithProxy>true</registerWithProxy>
            <proxy1_address>{{local_ip}}</proxy1_address>
            <proxy1_port>5060</proxy1_port>
        </sipProxies>
        
        <sipLines>
            <line button="1">
                <featureID>9</featureID>
                <featureLabel>{{label}}</featureLabel>
                <name>{{extension}}</name>
                <displayName>{{label}}</displayName>
                <contact>{{extension}}</contact>
                <authName>{{extension}}</authName>
                <authPassword>{{secret}}</authPassword>
            </line>
        </sipLines>
    </sipProfile>

    <userLocale>
        <winCharSet>UTF-8</winCharSet>
        <langCode>en-US</langCode>
        <backgroundFile>{{wallpaper_url}}</backgroundFile>
    </userLocale>

    <provisioning>
        <profile_rule>{{target_url}}/$MA.xml</profile_rule>
        <resync_on_reset>true</resync_on_reset>
    </provisioning>
</device>
''';

  static Future<String> getTemplateForModel(String model) async {
    final normalized = model.trim().toUpperCase();

    // 1. Check DB for custom overrides
    final dbTemplate = await DatabaseHelper.instance.getTemplateByModel(normalized);
    if (dbTemplate != null && dbTemplate.isNotEmpty) {
      return dbTemplate;
    }

    // 2. Built-in Detection
    if (normalized.contains('CISCO') || normalized.contains('88') || normalized.contains('78')) {
      return fallbackCiscoTemplate;
    } else if (normalized.contains('VVX') || normalized.contains('EDGE') || normalized.contains('TRIO')) {
      return fallbackPolycomTemplate;
    }

    // 3. Default Yealink
    return fallbackYealinkTemplate.replaceAll('{{model}}', normalized);
  }

  static Future<String> getContentType(String model) async {
    final normalized = model.trim().toUpperCase();
    if (normalized.contains('VVX') || normalized.contains('EDGE') || normalized.contains('CISCO')) {
      return 'application/xml'; // Poly & Cisco use XML
    }
    return 'text/plain'; // Yealink uses .cfg
  }
}
