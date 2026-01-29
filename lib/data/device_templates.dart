/// Stores configuration templates for various handset manufacturers.
class DeviceTemplates {
  
  // -- CONFIGURATION CONSTANTS --
  static const String telstraTarget = "http://polydms.digitalbusiness.telstra.com/dms/bootstrap";

  // -- TEMPLATE 1: YEALINK GENERIC (T4x, T5x) --
  // Uses .cfg format.
  // Includes 'static.auto_provision' to trigger the Server Hop.
  static const String yealinkGeneric = '''
#!version:1.0.0.1
## -- Pocket Provisioner v0.0.1 Generated Config -- ##

# SIP Account Settings
account.1.enable = 1
account.1.label = {{label}}
account.1.display_name = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
account.1.sip_server.1.address = {{local_ip}}
account.1.sip_server.1.port = 5060
account.1.sip_server.1.transport_type = 1

# Local Customizations (Example: Button Layout)
# This clones the layout to every phone using this template
linekey.1.type = 15
linekey.1.line = 1
linekey.1.label = Line 1
linekey.2.type = 0
linekey.3.type = 0

# Wallpaper Logic
# If a public URL is set, the phone fetches it from the internet.
# If not, it fetches from this Android phone.
phone_setting.backgrounds = {{wallpaper_url}}

# SERVER HOP: Point to Telstra for next boot
static.auto_provision.server.url = {{target_url}}
static.auto_provision.enable = 1
static.auto_provision.power_on = 1
''';

  // -- TEMPLATE 2: POLYCOM VVX (XML) --
  // Uses .xml format.
  // Updated with Background Image support for VVX series
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
  
  <bg 
    bg.color.selection="2,1" 
    bg.color.bm.1.name="{{wallpaper_url}}" 
  />

  <DEVICE device.prov.serverName="{{target_url}}" />
</PHONE_CONFIG>
''';

  /// Selects the correct template string based on model name
  static String getTemplateForModel(String model) {
    final m = model.toUpperCase();
    if (m.contains("VVX") || m.contains("POLY")) {
      return polycomGeneric;
    }
    // Default to Yealink for T48, T58, etc.
    return yealinkGeneric;
  }
  
  /// Determines the Content-Type header (Text vs XML)
  static String getContentType(String model) {
    final m = model.toUpperCase();
    if (m.contains("VVX") || m.contains("POLY")) {
      return 'application/xml';
    }
    return 'text/plain';
  }
}
