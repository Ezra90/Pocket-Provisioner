import 'dart:convert';
import 'button_key.dart';

/// Per-device override settings for provisioning configuration.
/// All fields default to null meaning "inherited / use global default".
class DeviceSettings {
  // SIP & Registration
  String? sipServer;
  String? sipPort;
  String? transport; // UDP | TCP | TLS | DNS-SRV
  String? regExpiry;
  String? outboundProxyHost;
  String? outboundProxyPort;
  String? backupServer;
  String? backupPort;

  // Display & Audio
  String? ringtone;
  String? screensaverTimeout;

  // Security
  String? adminPassword;
  bool? webUiEnabled;

  // Network
  String? voiceVlanId;
  String? dataVlanId;
  bool? cdpLldpEnabled;

  // Call Features
  bool? autoAnswer;
  String? autoAnswerMode; // 'on' | 'intercom-only'
  bool? dndDefault;
  bool? callWaiting;
  String? cfwAlways;
  String? cfwBusy;
  String? cfwNoAnswer;
  String? voicemailNumber;

  // Provisioning
  String? provisioningUrl;
  String? ntpServer;
  String? timezone;
  String? dstEnable; // Daylight saving time (Yealink: 0/1/2)

  // Diagnostics
  String? syslogServer; // IP of remote syslog server
  String? debugLevel; // Syslog verbosity (Cisco: 0-3)

  // Call Features (extended)
  String? dialPlan; // Digitmap / dial plan string

  /// Per-device button layout.  null = use model-default from ButtonLayoutService.
  List<ButtonKey>? buttonLayout;

  DeviceSettings({
    this.sipServer,
    this.sipPort,
    this.transport,
    this.regExpiry,
    this.outboundProxyHost,
    this.outboundProxyPort,
    this.backupServer,
    this.backupPort,
    this.ringtone,
    this.screensaverTimeout,
    this.adminPassword,
    this.webUiEnabled,
    this.voiceVlanId,
    this.dataVlanId,
    this.cdpLldpEnabled,
    this.autoAnswer,
    this.autoAnswerMode,
    this.dndDefault,
    this.callWaiting,
    this.cfwAlways,
    this.cfwBusy,
    this.cfwNoAnswer,
    this.voicemailNumber,
    this.provisioningUrl,
    this.ntpServer,
    this.timezone,
    this.dstEnable,
    this.syslogServer,
    this.debugLevel,
    this.dialPlan,
    this.buttonLayout,
  });

  /// True if any field has been set (i.e. not all inherited).
  bool get hasOverrides =>
      sipServer != null ||
      sipPort != null ||
      transport != null ||
      regExpiry != null ||
      outboundProxyHost != null ||
      outboundProxyPort != null ||
      backupServer != null ||
      backupPort != null ||
      ringtone != null ||
      screensaverTimeout != null ||
      adminPassword != null ||
      webUiEnabled != null ||
      voiceVlanId != null ||
      dataVlanId != null ||
      cdpLldpEnabled != null ||
      autoAnswer != null ||
      autoAnswerMode != null ||
      dndDefault != null ||
      callWaiting != null ||
      cfwAlways != null ||
      cfwBusy != null ||
      cfwNoAnswer != null ||
      voicemailNumber != null ||
      provisioningUrl != null ||
      ntpServer != null ||
      timezone != null ||
      dstEnable != null ||
      syslogServer != null ||
      debugLevel != null ||
      dialPlan != null ||
      (buttonLayout != null && buttonLayout!.any((k) => k.type != 'none'));

  /// Deep-copies this object.
  DeviceSettings clone() => DeviceSettings(
        sipServer: sipServer,
        sipPort: sipPort,
        transport: transport,
        regExpiry: regExpiry,
        outboundProxyHost: outboundProxyHost,
        outboundProxyPort: outboundProxyPort,
        backupServer: backupServer,
        backupPort: backupPort,
        ringtone: ringtone,
        screensaverTimeout: screensaverTimeout,
        adminPassword: adminPassword,
        webUiEnabled: webUiEnabled,
        voiceVlanId: voiceVlanId,
        dataVlanId: dataVlanId,
        cdpLldpEnabled: cdpLldpEnabled,
        autoAnswer: autoAnswer,
        autoAnswerMode: autoAnswerMode,
        dndDefault: dndDefault,
        callWaiting: callWaiting,
        cfwAlways: cfwAlways,
        cfwBusy: cfwBusy,
        cfwNoAnswer: cfwNoAnswer,
        voicemailNumber: voicemailNumber,
        provisioningUrl: provisioningUrl,
        ntpServer: ntpServer,
        timezone: timezone,
        dstEnable: dstEnable,
        syslogServer: syslogServer,
        debugLevel: debugLevel,
        dialPlan: dialPlan,
        buttonLayout: buttonLayout?.map((k) => k.clone()).toList(),
      );

  Map<String, dynamic> toJson() => {
        if (sipServer != null) 'sip_server': sipServer,
        if (sipPort != null) 'sip_port': sipPort,
        if (transport != null) 'transport': transport,
        if (regExpiry != null) 'reg_expiry': regExpiry,
        if (outboundProxyHost != null) 'outbound_proxy_host': outboundProxyHost,
        if (outboundProxyPort != null) 'outbound_proxy_port': outboundProxyPort,
        if (backupServer != null) 'backup_server': backupServer,
        if (backupPort != null) 'backup_port': backupPort,
        if (ringtone != null) 'ringtone': ringtone,
        if (screensaverTimeout != null) 'screensaver_timeout': screensaverTimeout,
        if (adminPassword != null) 'admin_password': adminPassword,
        if (webUiEnabled != null) 'web_ui_enabled': webUiEnabled,
        if (voiceVlanId != null) 'voice_vlan_id': voiceVlanId,
        if (dataVlanId != null) 'data_vlan_id': dataVlanId,
        if (cdpLldpEnabled != null) 'cdp_lldp_enabled': cdpLldpEnabled,
        if (autoAnswer != null) 'auto_answer': autoAnswer,
        if (autoAnswerMode != null) 'auto_answer_mode': autoAnswerMode,
        if (dndDefault != null) 'dnd_default': dndDefault,
        if (callWaiting != null) 'call_waiting': callWaiting,
        if (cfwAlways != null) 'cfw_always': cfwAlways,
        if (cfwBusy != null) 'cfw_busy': cfwBusy,
        if (cfwNoAnswer != null) 'cfw_no_answer': cfwNoAnswer,
        if (voicemailNumber != null) 'voicemail_number': voicemailNumber,
        if (provisioningUrl != null) 'provisioning_url': provisioningUrl,
        if (ntpServer != null) 'ntp_server': ntpServer,
        if (timezone != null) 'timezone': timezone,
        if (dstEnable != null) 'dst_enable': dstEnable,
        if (syslogServer != null) 'syslog_server': syslogServer,
        if (debugLevel != null) 'debug_level': debugLevel,
        if (dialPlan != null) 'dial_plan': dialPlan,
        if (buttonLayout != null && buttonLayout!.isNotEmpty)
          'button_layout': buttonLayout!.map((k) => k.toJson()).toList(),
      };

  factory DeviceSettings.fromJson(Map<String, dynamic> m) => DeviceSettings(
        sipServer: m['sip_server'] as String?,
        sipPort: m['sip_port'] as String?,
        transport: m['transport'] as String?,
        regExpiry: m['reg_expiry'] as String?,
        outboundProxyHost: m['outbound_proxy_host'] as String?,
        outboundProxyPort: m['outbound_proxy_port'] as String?,
        backupServer: m['backup_server'] as String?,
        backupPort: m['backup_port'] as String?,
        ringtone: m['ringtone'] as String?,
        screensaverTimeout: m['screensaver_timeout'] as String?,
        adminPassword: m['admin_password'] as String?,
        webUiEnabled: m['web_ui_enabled'] as bool?,
        voiceVlanId: m['voice_vlan_id'] as String?,
        dataVlanId: m['data_vlan_id'] as String?,
        cdpLldpEnabled: m['cdp_lldp_enabled'] as bool?,
        autoAnswer: m['auto_answer'] as bool?,
        autoAnswerMode: m['auto_answer_mode'] as String?,
        dndDefault: m['dnd_default'] as bool?,
        callWaiting: m['call_waiting'] as bool?,
        cfwAlways: m['cfw_always'] as String?,
        cfwBusy: m['cfw_busy'] as String?,
        cfwNoAnswer: m['cfw_no_answer'] as String?,
        voicemailNumber: m['voicemail_number'] as String?,
        provisioningUrl: m['provisioning_url'] as String?,
        ntpServer: m['ntp_server'] as String?,
        timezone: m['timezone'] as String?,
        dstEnable: m['dst_enable'] as String?,
        syslogServer: m['syslog_server'] as String?,
        debugLevel: m['debug_level'] as String?,
        dialPlan: m['dial_plan'] as String?,
        buttonLayout: m['button_layout'] != null
            ? (m['button_layout'] as List<dynamic>)
                .map((e) => ButtonKey.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
      );

  /// Encode to JSON string for DB storage.
  String toJsonString() => jsonEncode(toJson());

  /// Decode from a JSON string stored in the DB; returns null on failure.
  static DeviceSettings? fromJsonString(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return DeviceSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
