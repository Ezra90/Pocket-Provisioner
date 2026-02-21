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
    // [^#/^!>] excludes the first char being a section/control sigil
    final regex = RegExp(r'\{\{([^#/^!>][^}]*)\}\}');
    return regex
        .allMatches(source)
        .map((m) => m.group(1)!.trim())
        .toSet()
        .toList();
  }

  /// Maps a device model string to the canonical template key.
  static String resolveTemplateKey(String model) {
    final upper = model.toUpperCase();
    // Check for Cisco explicitly or Cisco model numbers with word boundaries
    if (upper.contains('CISCO') ||
        RegExp(r'(?:^|[^0-9])(?:78|88)\d{2}(?:[^0-9]|$)').hasMatch(upper)) {
      return 'cisco_88xx';
    }
    if (upper.contains('POLY') ||
        upper.contains('VVX') ||
        upper.contains('EDGE')) {
      return 'polycom_vvx';
    }
    return 'yealink_t4x';
  }

  /// Maps a ButtonKey type string to its Yealink DSS key type code.
  static int buttonTypeToCode(String type) {
    return switch (type) {
      'blf' => 16,
      'speeddial' => 13,
      'line' => 15,
      'dtmf' => 34,
      'park' => 10,
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
    String? regExpires,
    String? outboundProxyHost,
    String? outboundProxyPort,
    String? backupServer,
    String? backupPort,
    String? voiceVlanId,
    String? dataVlanId,
    String? wallpaperUrl,
    String? ntpServer,
    String? timezone,
    String? timezoneName,
    String? gmtOffset,
    String? adminPassword,
    String? voicemailNumber,
    List<ButtonKey>? lineKeys,
    Map<String, String>? extToLabel,
  }) {
    final bool hasOutboundProxy =
        outboundProxyHost != null && outboundProxyHost.isNotEmpty;
    final bool hasBackupServer =
        backupServer != null && backupServer.isNotEmpty;
    final bool vlanEnabled =
        voiceVlanId != null && voiceVlanId.isNotEmpty;
    final bool hasVoicemail =
        voicemailNumber != null && voicemailNumber.isNotEmpty;

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
      'voice_vlan_id': voiceVlanId ?? '',
      'data_vlan_id': dataVlanId ?? '',
      'wallpaper_url': wallpaperUrl ?? '',
      'ntp_server': ntpServer ?? '0.pool.ntp.org',
      'timezone': timezone ?? 'UTC',
      'timezone_name': timezoneName ?? 'UTC',
      'gmt_offset': gmtOffset ?? '0',
      'admin_password': adminPassword ?? '',
      'provisioning_url': provisioningUrl,
      'provision_user': extension,
      'provision_pass': secret,
      'ring_type': 'Ring1.wav',
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
          'expires': regExpires ?? '3600',
          'has_outbound_proxy': hasOutboundProxy,
          'outbound_proxy_host': outboundProxyHost ?? '',
          'outbound_proxy_port': outboundProxyPort ?? '5060',
          'has_backup_server': hasBackupServer,
          'backup_server': backupServer ?? '',
          'backup_port': backupPort ?? '5060',
          'has_voicemail': hasVoicemail,
          'voicemail_number': voicemailNumber ?? '',
        },
      ],
      'line_keys': lineKeysList,
      'attendant_keys': attendantKeysList,
      'expansion_keys': <Map<String, dynamic>>[],
      'remote_phonebooks': <Map<String, dynamic>>[],
    };
  }
}
