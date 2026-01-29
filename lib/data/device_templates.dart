import '../data/database_helper.dart';

class DeviceTemplates {
  
  // Default fallback if nothing is set in App Settings
  static const String defaultTarget = "http://polydms.digitalbusiness.telstra.com/dms/bootstrap";

  // --- TEMPLATE 1: YEALINK GENERIC ---
  static const String yealinkGeneric = '''
#!version:1.0.0.1
## -- Pocket Provisioner v0.0.2 -- ##

# 1. ACCOUNT SETTINGS (Initial Setup)
account.1.enable = 1
account.1.label = {{label}}
account.1.display_name = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
account.1.sip_server.1.address = {{local_ip}}
account.1.sip_server.1.port = 5060
account.1.sip_server.1.transport_type = 1

# 2. LOCAL CUSTOMIZATIONS
phone_setting.backgrounds = {{wallpaper_url}}

# 3. SERVER HOP (The Handover)
# Points the phone to the final destination (Telstra/3CX/FreePBX)
static.auto_provision.server.url = {{target_url}}
static.auto_provision.server.username = {{extension}}
static.auto_provision.server.password = {{secret}}
static.auto_provision.enable = 1
static.auto_provision.power_on = 1

# Disable Quick Setup to automate the handover
features.show_quick_setup.enable = 0
''';

  // --- TEMPLATE 2: POLYCOM VVX ---
  static const String polycomGeneric = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PHONE_CONFIG>
  <REGISTRATION
    reg.1.displayName="{{label}}"
    reg.1.address="{{extension}}"
    reg.1.auth.userId="{{extension}}"
    reg.1.auth.password="{{secret}}"
    reg.1.server.1.address="{{local_ip}}"
    reg.1.server.1.port="5060"
    reg.1.server.1.transport="TCPOnly"
  />
  
  <bg bg.color.selection="2,1" bg.color.bm.1.name="{{wallpaper_url}}" />

  <DEVICE 
    device.prov.serverName="{{target_url}}"
    device.prov.user="{{extension}}"
    device.prov.password="{{secret}}"
    device.prov.serverType="HTTP"
  />
</PHONE_CONFIG>
''';

  static Future<String> getTemplateForModel(String model) async {
    final custom = await DatabaseHelper.instance.getTemplate(model);
    if (custom != null) return custom['content'] as String;

    if (model.toUpperCase().contains("POLY") || model.toUpperCase().contains("VVX") || model.toUpperCase().contains("EDGE")) {
      return polycomGeneric;
    }
    return yealinkGeneric;
  }
  
  static Future<String> getContentType(String model) async {
    final custom = await DatabaseHelper.instance.getTemplate(model);
    if (custom != null) return custom['content_type'] as String;

    if (model.toUpperCase().contains("POLY") || model.toUpperCase().contains("VVX") || model.toUpperCase().contains("EDGE")) {
      return 'application/xml';
    }
    return 'text/plain';
  }
}
