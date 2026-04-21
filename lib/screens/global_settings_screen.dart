import 'package:flutter/material.dart';
import '../services/global_settings.dart';

/// Global job-environment settings screen, accessible from the dashboard
/// via the ⚙ icon.
///
/// Settings here apply to *all* devices unless overridden per-device in
/// [DeviceSettingsEditorScreen].
///
/// ## Provisioning Modes
///
/// ### DMS / Carrier Mode (Telstra / Broadworks)
/// Generates a minimal bootstrap config pointing the handset at the carrier
/// DMS server.  After the first boot the phone auto-provisions from DMS and
/// receives its full configuration (SIP server, features, etc.) from there.
/// This bypasses the handset's built-in Telstra / Broadworks qsetup wizard.
///
/// ### Standalone / FreePBX Mode
/// Generates a complete config so the phone registers directly with an
/// on-premise PBX (FreePBX, Asterisk, etc.) that does not have DMS
/// integration.  All SIP details are provisioned in a single pass.
class GlobalSettingsScreen extends StatefulWidget {
  const GlobalSettingsScreen({super.key});

  @override
  State<GlobalSettingsScreen> createState() => _GlobalSettingsScreenState();
}

class _GlobalSettingsScreenState extends State<GlobalSettingsScreen> {
  bool _loading = true;
  late String _mode;

  // DMS mode
  late final TextEditingController _dmsUrlCtrl;

  // Standalone mode
  late final TextEditingController _sipServerCtrl;
  late final TextEditingController _sipPortCtrl;
  String? _transport;

  // Common
  late final TextEditingController _ntpServerCtrl;
  late final TextEditingController _timezoneCtrl;
  late final TextEditingController _adminPasswordCtrl;
  late final TextEditingController _voiceVlanCtrl;

  @override
  void initState() {
    super.initState();
    _dmsUrlCtrl = TextEditingController();
    _sipServerCtrl = TextEditingController();
    _sipPortCtrl = TextEditingController();
    _ntpServerCtrl = TextEditingController();
    _timezoneCtrl = TextEditingController();
    _adminPasswordCtrl = TextEditingController();
    _voiceVlanCtrl = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _dmsUrlCtrl.dispose();
    _sipServerCtrl.dispose();
    _sipPortCtrl.dispose();
    _ntpServerCtrl.dispose();
    _timezoneCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _voiceVlanCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final data = await GlobalSettings.load();
    if (!mounted) return;
    setState(() {
      _mode = data.mode;
      _dmsUrlCtrl.text = data.dmsUrl ?? '';
      _sipServerCtrl.text = data.sipServer ?? '';
      _sipPortCtrl.text = data.sipPort ?? '';
      _transport = data.transport;
      _ntpServerCtrl.text = data.ntpServer ?? '';
      _timezoneCtrl.text = data.timezone ?? '';
      _adminPasswordCtrl.text = data.adminPassword ?? '';
      _voiceVlanCtrl.text = data.voiceVlanId ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    await GlobalSettings.setMode(_mode);
    await GlobalSettings.setDmsUrl(_dmsUrlCtrl.text);
    await GlobalSettings.setSipServer(_sipServerCtrl.text);
    await GlobalSettings.setSipPort(_sipPortCtrl.text);
    await GlobalSettings.setTransport(_transport);
    await GlobalSettings.setNtpServer(_ntpServerCtrl.text);
    await GlobalSettings.setTimezone(_timezoneCtrl.text);
    await GlobalSettings.setAdminPassword(_adminPasswordCtrl.text);
    await GlobalSettings.setVoiceVlanId(_voiceVlanCtrl.text);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    Navigator.pop(context, true); // signal that settings changed
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType keyboard = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDms = _mode == GlobalSettings.modeDms;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Settings'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, color: Colors.white),
            label:
                const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Provisioning Mode ─────────────────────────────────────────
            _SectionHeader(
              icon: '🔀',
              title: 'Provisioning Mode',
              subtitle:
                  'Select how handsets are provisioned on this job.',
            ),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: GlobalSettings.modeDms,
                      groupValue: _mode,
                      onChanged: (v) => setState(() => _mode = v!),
                      title: const Text(
                        'DMS / Carrier Mode',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Telstra / Broadworks – app bootstraps the handset '
                        'with auth credentials and a DMS URL, then the DMS '
                        'server delivers the full configuration on next boot. '
                        'Bypasses the handset\'s built-in qsetup wizard.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    RadioListTile<String>(
                      value: GlobalSettings.modeStandalone,
                      groupValue: _mode,
                      onChanged: (v) => setState(() => _mode = v!),
                      title: const Text(
                        'Standalone / FreePBX Mode',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'On-premise PBX without DMS – app provisions all '
                        'details (SIP server, credentials, features) in a '
                        'single pass.  Phone connects directly to your PBX '
                        '(FreePBX, Asterisk, etc.) with no secondary hop.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Mode-specific settings ─────────────────────────────────────
            if (isDms) ...[
              _SectionHeader(
                icon: '☁️',
                title: 'DMS / Carrier Settings',
                subtitle:
                    'Configure the carrier DMS server that phones will '
                    'auto-provision from after the initial bootstrap.',
              ),
              _field(
                _dmsUrlCtrl,
                'Target DMS / EPM Server URL',
                hint: 'e.g. https://dms.telstra.com/prov',
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'In DMS mode the SIP server is supplied by the DMS – '
                        'leave the SIP Server field blank in per-device '
                        'settings unless you need to override it for a '
                        'specific handset.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              _SectionHeader(
                icon: '🏢',
                title: 'Standalone / FreePBX Settings',
                subtitle:
                    'SIP server details for your on-premise PBX.  Applied '
                    'globally and may be overridden per device.',
              ),
              _field(
                _sipServerCtrl,
                'SIP / PBX Server Address',
                hint: 'e.g. 192.168.1.10 or pbx.example.com',
              ),
              _field(
                _sipPortCtrl,
                'SIP Port',
                hint: '5060',
                keyboard: TextInputType.number,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String?>(
                  value: _transport,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Transport Protocol',
                    hintText: 'Default (UDP)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                        value: null, child: Text('Default (UDP)')),
                    DropdownMenuItem(value: 'UDP', child: Text('UDP')),
                    DropdownMenuItem(value: 'TCP', child: Text('TCP')),
                    DropdownMenuItem(value: 'TLS', child: Text('TLS')),
                    DropdownMenuItem(
                        value: 'DNS-SRV', child: Text('DNS-SRV')),
                  ],
                  onChanged: (v) => setState(() => _transport = v),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Common Settings ───────────────────────────────────────────
            _SectionHeader(
              icon: '⚙️',
              title: 'Common Settings',
              subtitle:
                  'Applied to all devices regardless of mode.  Per-device '
                  'overrides take precedence.',
            ),
            _field(
              _ntpServerCtrl,
              'NTP Server',
              hint: 'e.g. pool.ntp.org',
            ),
            _field(
              _timezoneCtrl,
              'Timezone Offset',
              hint: 'e.g. +10 or -5',
            ),
            _field(
              _voiceVlanCtrl,
              'Voice VLAN ID',
              hint: 'e.g. 100',
              keyboard: TextInputType.number,
            ),
            _field(
              _adminPasswordCtrl,
              'Default Admin Password',
              hint: 'Leave blank to use handset default',
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style:
                const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
