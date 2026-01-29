import '../data/database_helper.dart';

class DeviceTemplates {
  // Default hop target (Telstra PolyDMS example — users override in settings)
  static const String defaultTarget = "http://polydms.digitalbusiness.telstra.com/dms/bootstrap";

  // Fallback built-in template for Yealink phones
  // This is a solid, real-world starting point:
  // - Includes initial SIP account (for full/self-hosted mode — omit or comment for minimal DMS mode)
  // - Wallpaper
  // - Programmable/DSS keys via placeholder
  // - Auto-provision hop (with optional user/pass if added later)
  // - Common best-practice settings (web server enable, etc.)
  static const String fallbackYealinkTemplate = '''
#!version:1.0.0.1
## Pocket Provisioner Generated Config ##
## Model: {{model}} | Extension: {{extension}} | Label: {{label}} ##

# ------------------- ACCOUNT 1 (PRIMARY LINE) -------------------
# Comment out or remove this section in a custom "DMS-Minimal" template
account.1.enable = 1
account.1.label = {{label}}
account.1.display_name = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
account.1.sip_server.1.address = {{local_ip}}
account.1.sip_server.1.port = 5060

# ------------------- LOCAL CUSTOMIZATIONS -------------------
# Wallpaper / Background
phone_setting.backgrounds = {{wallpaper_url}}

# Enable web server (useful for post-provision tweaks)
webserver.enabled = 1
webserver.type = 0  # 0 = HTTP + HTTPS, 1 = HTTP only

# Other common locals (add more as needed)
local_time.time_zone = +10  # Australia/Brisbane (AEST)
local_time.ntp_server1 = pool.ntp.org

# ------------------- PROGRAMMABLE / DSS KEYS -------------------
{{dss_keys}}

# ------------------- AUTO-PROVISION HOP -------------------
# After initial boot, hop to production server
static.auto_provision.server.url = {{target_url}}
static.auto_provision.enable = 1
static.auto_provision.repeat.enable = 1
static.auto_provision.power_on = 1
static.auto_provision.weekly.enable = 0

# Optional: Add DMS credentials here if needed (future extension)
# static.auto_provision.user = your_dms_user
# static.auto_provision.password = your_dms_pass

# Force update/reboot to trigger hop quickly
static.auto_provision.update_file_enable = 1
static.firmware.url =

''';

  // Polycom fallback (minimal — expand later)
  static const String fallbackPolycomTemplate = '''
<?xml version="1.0" encoding="UTF-8"?>
<config>
  <provisioning>
    <server>{{target_url}}</server>
  </provisioning>
  <wallpaper>{{wallpaper_url}}</wallpaper>
  <!-- Add Polycom-specific DSS/softkeys here later -->
</config>
''';

  /// Retrieves the template for a given model.
  /// First checks DB for user-imported template, falls back to built-in.
  static Future<String> getTemplateForModel(String model) async {
    // Normalize model (e.g., case-insensitive, trim)
    final normalized = model.trim().toUpperCase();

    // Check DB first (user can import custom templates per model)
    final dbTemplate = await DatabaseHelper.instance.getTemplateByModel(normalized);
    if (dbTemplate != null && dbTemplate.isNotEmpty) {
      return dbTemplate;
    }

    // Built-in fallbacks
    if (normalized.contains('T') || normalized.contains('CP') || normalized.contains('VP')) {
      // Most Yealink models start with T, CP, or VP
      return fallbackYealinkTemplate.replaceAll('{{model}}', normalized);
    } else if (normalized.contains('VVX') || normalized.contains('TRIO') || normalized.contains('CCX')) {
      // Polycom/Poly models
      return fallbackPolycomTemplate;
    }

    // Ultimate generic fallback
    return fallbackYealinkTemplate.replaceAll('{{model}}', normalized);
  }

  /// Basic content-type detection (extend as needed)
  static Future<String> getContentType(String model) async {
    final normalized = model.trim().toUpperCase();
    if (normalized.contains('VVX') || normalized.contains('TRIO') || normalized.contains('CCX')) {
      return 'application/xml';
    }
    return 'text/plain'; // Yealink .cfg
  }
}
