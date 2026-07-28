import 'package:mustache_template/mustache_template.dart';
import '../models/button_key.dart';
import 'mustache_template_service.dart';

class MustacheRenderer {
  /// Regex that matches the `{{! META: {...} }}` comment block for stripping
  /// before template compilation.
  ///
  /// Uses a META-aware pattern ending in `} }}` (JSON root close + comment close).
  /// Nested JSON must not contain raw `}}` — use `} }` whitespace between closes
  /// (see template packaging). Prefer `chassis_svg_b64` over raw SVG in META.
  static final _metaCommentRegex =
      RegExp(r'\{\{!\s*META:\s*\{[\s\S]*\}\s*\}\}', multiLine: true);

  /// Renders [templateKey] using [variables].
  /// [htmlEscapeValues] is false so XML/CFG output is not double-escaped.
  static Future<String> render(
      String templateKey, Map<String, dynamic> variables) async {
    String source =
        await MustacheTemplateService.instance.loadTemplate(templateKey);
    // Strip the META metadata comment before compiling: it contains raw JSON
    // with curly-brace characters that can confuse the Mustache tokeniser.
    source = source.replaceFirst(_metaCommentRegex, '');
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
    // but NOT / (close), ! (comment), or > (partial). Handles optional triple braces.
    final regex = RegExp(r'\{\{\{?\s*[#^]?\s*([^/!>}\s][^}]*?)\s*\}?\}\}');
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
      'speed_dial' => 13,
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
    String? authUsername, // Auth username override (defaults to extension)
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
    String? firmwareUrl,
    List<ButtonKey>? lineKeys,
    Map<String, String>? extToLabel,
    String? phonebookUrl,
    String? polycomContactsDirectory,
  }) {
    // Use extension as auth username if not explicitly provided
    final effectiveAuthUsername = authUsername ?? extension;
    
    // Check if SIP server is configured — when false (DMS mode), accounts
    // should be disabled so the phone doesn't try to register until DMS
    // delivers the actual SIP credentials.
    final bool hasSipServer = sipServer.isNotEmpty;
    
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
    final bool hasWebUi = true;
    final bool hasCdpLldp = cdpLldpEnabled != null;
    final bool hasAutoAnswer = autoAnswer != null;
    final bool hasDnd = dndDefault != null;
    final bool hasCallWaiting = callWaiting != null;
    final bool hasCfwAlways = cfwAlways != null && cfwAlways.isNotEmpty;
    final bool hasCfwBusy = cfwBusy != null && cfwBusy.isNotEmpty;
    final bool hasCfwNoAnswer = cfwNoAnswer != null && cfwNoAnswer.isNotEmpty;
    final bool hasSyslog = syslogServer != null && syslogServer.isNotEmpty;
    const defaultDialPlan = '[1-9]xx|*xx.|*x.T|911|0T';
    final String effectiveDialPlan =
        (dialPlan != null && dialPlan.isNotEmpty) ? dialPlan : defaultDialPlan;
    const bool hasDialPlan = true;
    final bool hasFirmware = firmwareUrl != null && firmwareUrl.isNotEmpty;

    final keys = lineKeys ?? <ButtonKey>[];
    final labels = extToLabel ?? <String, String>{};

    String normalizeType(String type) {
      if (type == 'speeddial') return 'speed_dial';
      return type;
    }

    // id is 1-based handset linekey index (matches Quick-Provisioner keys_json.index)
    final List<Map<String, dynamic>> lineKeysList = keys
        .where((k) {
          final t = normalizeType(k.type);
          return t != 'none' && (t == 'line' || k.value.isNotEmpty);
        })
        .map((k) {
          final t = normalizeType(k.type);
          final effectiveLabel =
              k.label.isNotEmpty ? k.label : (labels[k.value] ?? k.value);
          return {
            'position': k.id,
            'type_code': buttonTypeToCode(t),
            'key_line': 1,
            'key_value': k.value,
            'key_label': effectiveLabel,
            'is_blf': t == 'blf',
            'pickup_code': '**',
          };
        })
        .toList();

    final blfKeys = keys
        .where((k) =>
            normalizeType(k.type) == 'blf' &&
            k.value.isNotEmpty &&
            k.value.trim() != extension.trim())
        .toList();
    final List<Map<String, dynamic>> attendantKeysList = [];
    for (var i = 0; i < blfKeys.length; i++) {
      final k = blfKeys[i];
      final effectiveLabel =
          k.label.isNotEmpty ? k.label : (labels[k.value] ?? k.value);
      attendantKeysList.add({
        'position': i + 1, // Poly resourceList indexes must be sequential
        'key_value': k.value,
        'key_label': effectiveLabel,
        'sip_server': sipServer,
      });
    }

    final speedDialKeys = keys
        .where((k) =>
            normalizeType(k.type) == 'speed_dial' && k.value.isNotEmpty)
        .toList();
    final List<Map<String, dynamic>> speedDialKeysList = [];
    for (var i = 0; i < speedDialKeys.length; i++) {
      final k = speedDialKeys[i];
      final effectiveLabel =
          k.label.isNotEmpty ? k.label : (labels[k.value] ?? k.value);
      speedDialKeysList.add({
        'position': i + 1,
        'key_value': k.value,
        'key_label': effectiveLabel,
      });
    }

    final bool hasExplicitPrimaryLine =
        keys.any((k) => normalizeType(k.type) == 'line');
    final List<Map<String, dynamic>> polyLineKeyAssignments = [];
    if (!hasExplicitPrimaryLine) {
      polyLineKeyAssignments.add({
        'position': 1,
        'category': 'Line',
        'index': 1,
        'has_index': true,
      });
    }
    for (final key in keys) {
      final t = normalizeType(key.type);
      if (t == 'none' || (t != 'line' && key.value.isEmpty)) {
        continue;
      }
      if (t == 'line') {
        polyLineKeyAssignments.add({
          'position': key.id,
          'category': 'Line',
          'index': 1,
          'has_index': true,
        });
        continue;
      }
      if (t == 'blf') {
        if (key.value.trim() == extension.trim()) {
          continue;
        }
        var renderPosition = key.id;
        if (!hasExplicitPrimaryLine && renderPosition >= 1) {
          renderPosition += 1;
        }
        final blfIndex =
            attendantKeysList.indexWhere((a) => a['key_value'] == key.value) +
                1;
        polyLineKeyAssignments.add({
          'position': renderPosition,
          'category': 'BLF',
          'index': 0,
          'has_index': true,
          'resource_position': blfIndex > 0 ? blfIndex : 1,
        });
        continue;
      }
      if (t == 'speed_dial') {
        var renderPosition = key.id;
        if (!hasExplicitPrimaryLine && renderPosition >= 1) {
          renderPosition += 1;
        }
        final sdIndex =
            speedDialKeysList.indexWhere((a) => a['key_value'] == key.value) +
                1;
        polyLineKeyAssignments.add({
          'position': renderPosition,
          'category': 'SpeedDial',
          'index': sdIndex > 0 ? sdIndex : 1,
          'has_index': true,
        });
      }
    }
    final bool polyTwoColumnDisplay = model == 'VVX1500' || model == 'VVX 1500';
    final bool isVvx1500 = polyTwoColumnDisplay;
    // VVX1500 does NOT support Flexible Line Key reassignment.
    // Home-screen hotkeys come from directory <sd> indexes instead.
    final List<Map<String, dynamic>> effectivePolyAssignments =
        isVvx1500 ? <Map<String, dynamic>>[] : polyLineKeyAssignments;
    if (effectivePolyAssignments.isNotEmpty) {
      effectivePolyAssignments
          .sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    }

    // VVX1500: video over UDP fragments SIP INVITEs — prefer TCP signalling.
    final String videoEnable = isVvx1500 ? '1' : '0';
    final String sipTransportMode =
        videoEnable == '1' ? 'TCPPreferred' : 'UDPOnly';
    final String videoAutoStart = videoEnable;

    final String contactsDir = polycomContactsDirectory ?? '';
    final bool hasPhonebook = (phonebookUrl != null && phonebookUrl.isNotEmpty) ||
        contactsDir.isNotEmpty;

    return {
      'mac_address': macAddress,
      'model': model,
      'has_sip_server': hasSipServer,
      'sip_server': sipServer,
      'sip_port': sipPort ?? '5060',
      'sip_transport_mode': sipTransportMode,
      'video_enable': videoEnable,
      'video_auto_start': videoAutoStart,
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
      'provisioning_base': provisioningUrl.endsWith('/')
          ? provisioningUrl
          : '$provisioningUrl/',
      'has_provisioning_base': provisioningUrl.isNotEmpty,
      'provision_user': extension,
      'provision_pass': secret,
      'has_screensaver_timeout': hasScreensaverTimeout,
      'screensaver_timeout': screensaverTimeout ?? '',
      'has_web_ui': hasWebUi,
      'web_ui_enabled': webUiEnabled == false ? '0' : '1',
      'is_web_ui_enabled': webUiEnabled != false,
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
      'dial_plan': effectiveDialPlan,
      'dst_enable': dstEnable ?? '0',
      'debug_level': debugLevel ?? '0',
      'has_firmware': hasFirmware,
      'firmware_url': firmwareUrl ?? '',
      'lines': [
        {
          'line_index': 1,
          'has_sip_server': hasSipServer,
          'label': displayName,
          'display_name': displayName,
          'user_name': extension,
          'auth_name': effectiveAuthUsername,
          'password': secret,
          'sip_server': sipServer,
          'sip_port': sipPort ?? '5060',
          'sip_transport_mode': sipTransportMode,
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
      'has_poly_line_key_assignments': effectivePolyAssignments.isNotEmpty,
      'poly_two_column_display': polyTwoColumnDisplay,
      'poly_line_key_assignments': effectivePolyAssignments,
      'has_attendant_keys': attendantKeysList.isNotEmpty,
      'attendant_keys': attendantKeysList,
      'has_speed_dial_keys': speedDialKeysList.isNotEmpty,
      'speed_dial_keys': speedDialKeysList,
      'expansion_keys': <Map<String, dynamic>>[],
      'has_phonebook': hasPhonebook,
      'phonebook_url': phonebookUrl ?? '',
      'polycom_contacts_directory': contactsDir,
      'has_polycom_contacts_directory': contactsDir.isNotEmpty,
      'remote_phonebooks': phonebookUrl != null && phonebookUrl.isNotEmpty
          ? [
              {
                'index': 1,
                'url': phonebookUrl,
                'name': displayName.isNotEmpty ? '$displayName Directory' : 'Company Directory',
              }
            ]
          : <Map<String, dynamic>>[],
    };
  }
}
