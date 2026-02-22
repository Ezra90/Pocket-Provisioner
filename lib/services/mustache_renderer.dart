import 'package:mustache_template/mustache_template.dart';
import '../models/button_key.dart';
import 'mustache_template_service.dart';

class MustacheRenderer {
  /// Renders [templateKey] using [variables].
  /// [htmlEscapeValues] is false so XML/CFG output is not double-escaped.
  static Future<String> render(
      String templateKey, Map<String, dynamic> variables) async {
    final source =
        await MustacheTemplateService.instance.loadTemplate(templateKey);
    final template = Template(source, htmlEscapeValues: false);
    return template.renderString(variables);
  }

  /// Extracts all simple variable names from `{{varName}}` tags in the template.
  /// Skips Mustache section/control tags: {{#section}}, {{/section}},
  /// {{^inverted}}, {{!comment}}, {{>partial}}.
  static Future<List<String>> extractVariables(String templateKey) async {
    final source =
        await MustacheTemplateService.instance.loadTemplate(templateKey);
    // Matches both {{variable}} and {{{unescapedVariable}}} tags while
    // excluding section/control sigils (#, /, ^, !, >).
    final regex = RegExp(r'\{\{\{?([^#/^!>{}][^{}]*?)\}?\}\}');
    return regex
        .allMatches(source)
        .map((m) => m.group(1)!.trim().replaceAll('&', '').trim())
        .toSet()
        .toList();
  }

  /// Extracts ALL tag names from a template — both simple variables (`{{foo}}`)
  /// and section/inverted tags (`{{#foo}}`, `{{^foo}}`).
  /// Excludes closing tags (`{{/foo}}`), comments (`{{!…}}`), and partials (`{{>…}}`).
  /// Returns a [Set] for O(1) membership checks.
  /// Use this to decide which UI features to show for a given handset model.
  static Future<Set<String>> extractAllTags(String templateKey) async {
    final source =
        await MustacheTemplateService.instance.loadTemplate(templateKey);
    // Match {{ optionally followed by # or ^ (open sections) or nothing (variables)
    // but NOT / (close), ! (comment), or > (partial).
    final regex = RegExp(r'\{\{\s*[#^]?\s*([^/!>}\s][^}]*?)\s*\}\}');
    return regex
        .allMatches(source)
        .map((m) => m.group(1)!.trim())
        .toSet();
  }

  /// Maps a device model string to the canonical template key.
  /// Checks custom/imported templates first, then falls back to brand matching.
  static Future<String> resolveTemplateKey(String model) async {
    // 1. Check if the model exactly matches a custom or imported template key
    final allTemplates = await MustacheTemplateService.instance.listAll();
    for (final template in allTemplates) {
      if (template.key.toLowerCase() == model.toLowerCase() ||
          template.displayName.toLowerCase() == model.toLowerCase()) {
        return template.key;
      }
    }

    // 2. Fall back to generic brand matching for bundled templates
    final upper = model.toUpperCase();
    if (upper.contains('CISCO') ||
        RegExp(r'(?:^|[^0-9])(?:78|88)\d{2}(?:[^0-9]|$)').hasMatch(upper)) {
      return 'cisco_88xx';
    }
    if (upper.contains('POLY') ||
        upper.contains('VVX') ||
        upper.contains('EDGE')) {
      return 'polycom_vvx';
    }

    // 3. Default fallback
    return 'yealink_t4x';
  }

  /// Maps a ButtonKey type string to its Yealink DSS key type code.
  static int buttonTypeToCode(String type) {
    return switch (type) {
      'blf' => 16,
      'speeddial' => 13,
      'line' => 15,
      'dtmf' => 34,
      'park' => 16, // BLF-based park monitoring for FreePBX/Asterisk
      _ => 0,
    };
  }

  /// Maps a transport protocol string to Yealink transport_type code.
  static int _transportToCode(String transport) {
    return switch (transport.toUpperCase()) {
      'UDP' => 0,
      'TCP' => 1,
      'TLS' => 2,
      'DNS-SRV' || 'DNSSRV' => 3,
      _ => 0,
    };
  }

  /// Converts a nullable bool to a '1'/'0' string flag for templates.
  static String _boolFlag(bool? value) => value == true ? '1' : '0';

  /// Builds the complete Mustache variable map for all three templates.
  static Map<String, dynamic> buildVariables({
    required String macAddress,
    required String extension,
    required String displayName,
    required String secret,
    required String model,
    required String sipServer,
    required String provisioningUrl,
    String? sipPort,
    String? transport,
    String? regExpiry,
    String? outboundProxyHost,
    String? outboundProxyPort,
    String? backupServer,
    String? backupPort,
    String? voiceVlanId,
    String? dataVlanId,
    String? wallpaperUrl,
    String? ringtoneUrl,
    String? ntpServer,
    String? timezone,
    String? timezoneName,
    String? gmtOffset,
    String? adminPassword,
    String? voicemailNumber,
    // Call features
    String? screensaverTimeout,
    bool? webUiEnabled,
    bool? cdpLldpEnabled,
    bool? autoAnswer,
    String? autoAnswerMode,
    bool? dndDefault,
    bool? callWaiting,
    String? cfwAlways,
    String? cfwBusy,
    String? cfwNoAnswer,
    // Diagnostics / extended provisioning
    String? syslogServer,
    String? dialPlan,
    String? dstEnable,
    String? debugLevel,
    List<ButtonKey>? lineKeys,
    Map<String, String>? extToLabel,
  }) {
    final bool hasOutboundProxy =
        outboundProxyHost != null && outboundProxyHost.isNotEmpty;
    final bool hasBackupServer =
        backupServer != null && backupServer.isNotEmpty;
    final bool vlanEnabled =
        voiceVlanId != null && voiceVlanId.isNotEmpty;
    final bool hasDataVlan = dataVlanId != null && dataVlanId.isNotEmpty;
    final bool hasVoicemail =
        voicemailNumber != null && voicemailNumber.isNotEmpty;
    final bool hasScreensaverTimeout =
        screensaverTimeout != null && screensaverTimeout.isNotEmpty;
    final bool hasWebUi = webUiEnabled != null;
    final bool hasCdpLldp = cdpLldpEnabled != null;
    final bool hasAutoAnswer = autoAnswer != null;
    final bool hasDnd = dndDefault != null;
    final bool hasCallWaiting = callWaiting != null;
    final bool hasCfwAlways = cfwAlways != null && cfwAlways.isNotEmpty;
    final bool hasCfwBusy = cfwBusy != null && cfwBusy.isNotEmpty;
    final bool hasCfwNoAnswer = cfwNoAnswer != null && cfwNoAnswer.isNotEmpty;
    final bool hasSyslog = syslogServer != null && syslogServer.isNotEmpty;
    final bool hasDialPlan = dialPlan != null && dialPlan.isNotEmpty;

    final keys = lineKeys ?? <ButtonKey>[];
    final labels = extToLabel ?? <String, String>{};

    final int lineCount = 1; // Currently single-line, but future-proof
    final List<Map<String, dynamic>> lineKeysList = keys
        .where((k) => k.type != 'none' && k.value.isNotEmpty)
        .map((k) {
          final effectiveLabel =
              k.label.isNotEmpty ? k.label : (labels[k.value] ?? k.value);
          return {
            'position': k.id + lineCount, // Offset past SIP lines
            'type_code': buttonTypeToCode(k.type),
            'key_line': 1,
            'key_value': k.value,
            'key_label': effectiveLabel,
            'is_blf': k.type == 'blf',
            'pickup_code': '**',
          };
        })
        .toList();

    final List<Map<String, dynamic>> attendantKeysList = keys
        .where((k) => k.type == 'blf' && k.value.isNotEmpty)
        .map((k) {
          final effectiveLabel =
              k.label.isNotEmpty ? k.label : (labels[k.value] ?? k.value);
          return {
            'position': k.id + lineCount,
            'key_value': k.value,
            'key_label': effectiveLabel,
            'sip_server': sipServer,
          };
        })
        .toList();

    return {
      'mac_address': macAddress,
      'model': model,
      'sip_server': sipServer,
      'sip_port': sipPort ?? '5060',
      'has_outbound_proxy': hasOutboundProxy,
      'outbound_proxy_host': outboundProxyHost ?? '',
      'outbound_proxy_port': outboundProxyPort ?? '5060',
      'has_backup_server': hasBackupServer,
      'backup_server': backupServer ?? '',
      'backup_port': backupPort ?? '5060',
      'vlan_enabled': vlanEnabled,
      'has_data_vlan': hasDataVlan,
      'voice_vlan_id': voiceVlanId ?? '',
      'data_vlan_id': dataVlanId ?? '',
      'wallpaper_url': wallpaperUrl ?? '',
      'ring_type': ringtoneUrl != null && ringtoneUrl.isNotEmpty
          ? ringtoneUrl
          : 'Ring1.wav',
      'has_custom_ringtone': ringtoneUrl != null && ringtoneUrl.isNotEmpty,
      'ringtone_url': ringtoneUrl ?? '',
      'ntp_server': ntpServer ?? '0.au.pool.ntp.org',
      'timezone': timezone ?? '+10',
      'timezone_name': timezoneName ?? 'Australia/Brisbane',
      'gmt_offset': gmtOffset ?? '36000',
      'admin_password': adminPassword ?? '',
      'provisioning_url': provisioningUrl,
      'provision_user': extension,
      'provision_pass': secret,
      'has_screensaver_timeout': hasScreensaverTimeout,
      'screensaver_timeout': screensaverTimeout ?? '',
      'has_web_ui': hasWebUi,
      'web_ui_enabled': _boolFlag(webUiEnabled),
      'is_web_ui_enabled': webUiEnabled == true,
      'has_cdp_lldp': hasCdpLldp,
      'cdp_lldp_enabled': _boolFlag(cdpLldpEnabled),
      'is_cdp_lldp_enabled': cdpLldpEnabled == true,
      'has_auto_answer': hasAutoAnswer,
      'auto_answer': _boolFlag(autoAnswer),
      'is_auto_answer': autoAnswer == true,
      'auto_answer_mode': autoAnswerMode ?? '',
      'is_intercom_only': autoAnswerMode == 'intercom-only',
      'has_dnd': hasDnd,
      'dnd_enabled': _boolFlag(dndDefault),
      'is_dnd_enabled': dndDefault == true,
      'has_call_waiting': hasCallWaiting,
      'call_waiting': _boolFlag(callWaiting),
      'is_call_waiting': callWaiting == true,
      'has_cfw_always': hasCfwAlways,
      'cfw_always': cfwAlways ?? '',
      'has_cfw_busy': hasCfwBusy,
      'cfw_busy': cfwBusy ?? '',
      'has_cfw_no_answer': hasCfwNoAnswer,
      'cfw_no_answer': cfwNoAnswer ?? '',
      'has_syslog': hasSyslog,
      'syslog_server': syslogServer ?? '',
      'has_dial_plan': hasDialPlan,
      'dial_plan': dialPlan ?? '',
      'dst_enable': dstEnable ?? '0',
      'debug_level': debugLevel ?? '0',
      'lines': [
        {
          'line_index': 1,
          'label': displayName,
          'display_name': displayName,
          'user_name': extension,
          'auth_name': extension,
          'password': secret,
          'sip_server': sipServer,
          'sip_port': sipPort ?? '5060',
          'transport': transport ?? 'UDP',
          'transport_code': _transportToCode(transport ?? 'UDP'),
          'expires': regExpiry ?? '3600',
          'has_outbound_proxy': hasOutboundProxy,
          'outbound_proxy_host': outboundProxyHost ?? '',
          'outbound_proxy_port': outboundProxyPort ?? '5060',
          'has_backup_server': hasBackupServer,
          'backup_server': backupServer ?? '',
          'backup_port': backupPort ?? '5060',
          'has_voicemail': hasVoicemail,
          'voicemail_number': voicemailNumber ?? '',
          'has_auto_answer': hasAutoAnswer,
          'auto_answer': _boolFlag(autoAnswer),
          'has_cfw_always': hasCfwAlways,
          'cfw_always': cfwAlways ?? '',
          'has_cfw_busy': hasCfwBusy,
          'cfw_busy': cfwBusy ?? '',
          'has_cfw_no_answer': hasCfwNoAnswer,
          'cfw_no_answer': cfwNoAnswer ?? '',
        },
      ],
      'line_keys': lineKeysList,
      'has_line_keys': lineKeysList.isNotEmpty,
      'has_attendant_keys': attendantKeysList.isNotEmpty,
      'attendant_keys': attendantKeysList,
      'expansion_keys': <Map<String, dynamic>>[],
      'remote_phonebooks': <Map<String, dynamic>>[],
    };
  }
}
