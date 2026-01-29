import '../data/database_helper.dart';

class DeviceTemplates {
  
  static const String telstraTarget = "http://polydms.digitalbusiness.telstra.com/dms/bootstrap";

  static const String yealinkGeneric = '''
#!version:1.0.0.1
## Default Yealink Template
account.1.enable = 1
account.1.label = {{label}}
account.1.display_name = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
account.1.sip_server.1.address = {{local_ip}}
account.1.sip_server.1.port = 5060
phone_setting.backgrounds = {{wallpaper_url}}
static.auto_provision.server.url = {{target_url}}
static.auto_provision.enable = 1
''';

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
  />
  <bg bg.color.selection="2,1" bg.color.bm.1.name="{{wallpaper_url}}" />
  <DEVICE device.prov.serverName="{{target_url}}" />
</PHONE_CONFIG>
''';

  static Future<String> getTemplateForModel(String model) async {
    final custom = await DatabaseHelper.instance.getTemplate(model);
    if (custom != null) {
      return custom['content'] as String;
    }

    if (model.toUpperCase().contains("VVX") || model.toUpperCase().contains("POLY")) {
      return polycomGeneric;
    }
    return yealinkGeneric;
  }
  
  static Future<String> getContentType(String model) async {
    final custom = await DatabaseHelper.instance.getTemplate(model);
    if (custom != null) {
      return custom['content_type'] as String;
    }

    if (model.toUpperCase().contains("VVX") || model.toUpperCase().contains("POLY")) {
      return 'application/xml';
    }
    return 'text/plain';
  }
}
