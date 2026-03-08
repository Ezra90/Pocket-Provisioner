import 'package:shared_preferences/shared_preferences.dart';

/// Global provisioning configuration that applies to all devices unless
/// overridden by per-device [DeviceSettings].
///
/// Two operating modes are supported:
///
/// **DMS / Carrier Mode** – used for Telstra / Broadworks deployments.
/// The app generates a minimal bootstrap config that points the handset at
/// the carrier DMS server.  The DMS then delivers the full phone
/// configuration on the next boot, bypassing the handset's built-in qsetup
/// wizard.  Typically the SIP server is *not* set here because the DMS
/// supplies it.
///
/// **Standalone / FreePBX Mode** – used for on-premise PBX deployments
/// (FreePBX, Asterisk, etc.) that do not have DMS integration.  The app
/// generates a *complete* config including all SIP registration details.
/// The phone connects directly to the PBX without a secondary DMS hop.
class GlobalSettings {
  // ── Mode constants ──────────────────────────────────────────────────────────

  /// DMS / Carrier mode (Telstra / Broadworks).
  static const String modeDms = 'dms';

  /// Standalone / FreePBX mode (on-premise PBX without DMS).
  static const String modeStandalone = 'standalone';

  // ── SharedPreferences keys ──────────────────────────────────────────────────

  static const String _keyMode = 'provisioning_mode';

  // DMS mode
  static const String _keyDmsUrl = 'global_dms_url';

  // Standalone mode
  static const String _keySipServer = 'global_sip_server';
  static const String _keySipPort = 'global_sip_port';
  static const String _keyTransport = 'global_transport';

  // Common settings
  static const String _keyNtpServer = 'global_ntp_server';
  static const String _keyTimezone = 'global_timezone';
  static const String _keyAdminPassword = 'global_admin_password';
  static const String _keyVoiceVlanId = 'global_voice_vlan_id';

  // ── Read ────────────────────────────────────────────────────────────────────

  static Future<String> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMode) ?? modeDms;
  }

  static Future<bool> isDmsMode() async => await getMode() == modeDms;

  static Future<String?> getDmsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyDmsUrl);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getSipServer() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keySipServer);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getSipPort() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keySipPort);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getTransport() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyTransport);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getNtpServer() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyNtpServer);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyTimezone);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getAdminPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyAdminPassword);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Future<String?> getVoiceVlanId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyVoiceVlanId);
    return (v != null && v.isNotEmpty) ? v : null;
  }

  // ── Write ───────────────────────────────────────────────────────────────────

  static Future<void> setMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode);
  }

  static Future<void> setDmsUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDmsUrl, value.trim());
  }

  static Future<void> setSipServer(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySipServer, value.trim());
  }

  static Future<void> setSipPort(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySipPort, value.trim());
  }

  static Future<void> setTransport(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTransport, value?.trim() ?? '');
  }

  static Future<void> setNtpServer(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNtpServer, value.trim());
  }

  static Future<void> setTimezone(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimezone, value.trim());
  }

  static Future<void> setAdminPassword(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAdminPassword, value.trim());
  }

  static Future<void> setVoiceVlanId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVoiceVlanId, value.trim());
  }

  // ── Convenience: load all into a single struct ──────────────────────────────

  static Future<GlobalSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();

    String? _get(String key) {
      final v = prefs.getString(key);
      return (v != null && v.isNotEmpty) ? v : null;
    }

    return GlobalSettingsData(
      mode: prefs.getString(_keyMode) ?? modeDms,
      dmsUrl: _get(_keyDmsUrl),
      sipServer: _get(_keySipServer),
      sipPort: _get(_keySipPort),
      transport: _get(_keyTransport),
      ntpServer: _get(_keyNtpServer),
      timezone: _get(_keyTimezone),
      adminPassword: _get(_keyAdminPassword),
      voiceVlanId: _get(_keyVoiceVlanId),
    );
  }
}

/// Immutable snapshot of all global settings.
class GlobalSettingsData {
  final String mode;
  final String? dmsUrl;
  final String? sipServer;
  final String? sipPort;
  final String? transport;
  final String? ntpServer;
  final String? timezone;
  final String? adminPassword;
  final String? voiceVlanId;

  bool get isDmsMode => mode == GlobalSettings.modeDms;

  const GlobalSettingsData({
    required this.mode,
    this.dmsUrl,
    this.sipServer,
    this.sipPort,
    this.transport,
    this.ntpServer,
    this.timezone,
    this.adminPassword,
    this.voiceVlanId,
  });

  // ── Config-generation helpers ─────────────────────────────────────────────

  /// Resolves the SIP server to embed in a generated config.
  ///
  /// Priority: per-device [override] → global standalone SIP server (or blank
  /// in DMS mode, since the DMS supplies the SIP server itself).
  String resolveSipServer(String? override) {
    if (override != null && override.isNotEmpty) return override;
    return isDmsMode ? '' : (sipServer ?? '');
  }

  /// Resolves the provisioning / DMS URL to embed in a generated config.
  ///
  /// Priority: per-device [override] → global DMS URL (DMS mode) →
  /// [serverUrl] (the app's own URL, used as a fallback in standalone mode).
  String resolveProvisioningUrl(String? override, {String? serverUrl}) {
    if (override != null && override.isNotEmpty) return override;
    return isDmsMode ? (dmsUrl ?? serverUrl ?? '') : (serverUrl ?? '');
  }
}
