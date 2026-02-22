import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../data/device_templates.dart';
import '../models/button_key.dart';
import '../models/device_settings.dart';
import '../services/wallpaper_service.dart';
import 'per_extension_button_editor.dart';

/// Info about another extension, used in the Clone From... dialog.
typedef ExtensionCloneInfo = ({
  String extension,
  String label,
  DeviceSettings? settings,
});

/// Return value from [DeviceSettingsEditorScreen].
class DeviceSettingsResult {
  final DeviceSettings settings;

  /// Updated wallpaper value (null = keep existing; empty string = clear to global default).
  final String? wallpaper;

  const DeviceSettingsResult({required this.settings, this.wallpaper});
}

/// Full-screen per-extension settings editor organised into expandable sections.
class DeviceSettingsEditorScreen extends StatefulWidget {
  final String extension;
  final String label;
  final String model;
  final DeviceSettings? initialSettings;
  final String? initialWallpaper;
  final List<WallpaperInfo> wallpapers;
  final List<ExtensionCloneInfo> otherExtensions;

  const DeviceSettingsEditorScreen({
    super.key,
    required this.extension,
    required this.label,
    required this.model,
    this.initialSettings,
    this.initialWallpaper,
    this.wallpapers = const [],
    this.otherExtensions = const [],
  });

  @override
  State<DeviceSettingsEditorScreen> createState() =>
      _DeviceSettingsEditorScreenState();
}

class _DeviceSettingsEditorScreenState
    extends State<DeviceSettingsEditorScreen> {
  // SIP & Registration
  late final TextEditingController _sipServerCtrl;
  late final TextEditingController _sipPortCtrl;
  String? _transport;
  late final TextEditingController _regExpiryCtrl;
  late final TextEditingController _outboundProxyHostCtrl;
  late final TextEditingController _outboundProxyPortCtrl;
  late final TextEditingController _backupServerCtrl;
  late final TextEditingController _backupPortCtrl;

  // Display & Audio
  String? _wallpaper;
  bool _wallpaperChanged = false;
  late List<WallpaperInfo> _wallpapers;
  late final TextEditingController _ringtoneCtrl;
  late final TextEditingController _screensaverTimeoutCtrl;

  // Security
  late final TextEditingController _adminPasswordCtrl;
  bool? _webUiEnabled;

  // Network
  late final TextEditingController _voiceVlanCtrl;
  late final TextEditingController _dataVlanCtrl;
  bool? _cdpLldpEnabled;

  // Call Features
  bool? _autoAnswer;
  String? _autoAnswerMode;
  bool? _dndDefault;
  bool? _callWaiting;
  late final TextEditingController _cfwAlwaysCtrl;
  late final TextEditingController _cfwBusyCtrl;
  late final TextEditingController _cfwNoAnswerCtrl;
  late final TextEditingController _voicemailCtrl;

  // Provisioning
  late final TextEditingController _provisioningUrlCtrl;
  late final TextEditingController _ntpServerCtrl;
  late final TextEditingController _timezoneCtrl;

  // Button Layout
  List<ButtonKey>? _buttonLayout;

  @override
  void initState() {
    super.initState();
    _wallpapers = List.from(widget.wallpapers);
    _wallpaper = widget.initialWallpaper;
    final s = widget.initialSettings;
    _sipServerCtrl = TextEditingController(text: s?.sipServer ?? '');
    _sipPortCtrl = TextEditingController(text: s?.sipPort ?? '');
    _transport = s?.transport;
    _regExpiryCtrl = TextEditingController(text: s?.regExpiry ?? '');
    _outboundProxyHostCtrl =
        TextEditingController(text: s?.outboundProxyHost ?? '');
    _outboundProxyPortCtrl =
        TextEditingController(text: s?.outboundProxyPort ?? '');
    _backupServerCtrl = TextEditingController(text: s?.backupServer ?? '');
    _backupPortCtrl = TextEditingController(text: s?.backupPort ?? '');
    _ringtoneCtrl = TextEditingController(text: s?.ringtone ?? '');
    _screensaverTimeoutCtrl =
        TextEditingController(text: s?.screensaverTimeout ?? '');
    _adminPasswordCtrl = TextEditingController(text: s?.adminPassword ?? '');
    _webUiEnabled = s?.webUiEnabled;
    _voiceVlanCtrl = TextEditingController(text: s?.voiceVlanId ?? '');
    _dataVlanCtrl = TextEditingController(text: s?.dataVlanId ?? '');
    _cdpLldpEnabled = s?.cdpLldpEnabled;
    _autoAnswer = s?.autoAnswer;
    _autoAnswerMode = s?.autoAnswerMode;
    _dndDefault = s?.dndDefault;
    _callWaiting = s?.callWaiting;
    _cfwAlwaysCtrl = TextEditingController(text: s?.cfwAlways ?? '');
    _cfwBusyCtrl = TextEditingController(text: s?.cfwBusy ?? '');
    _cfwNoAnswerCtrl = TextEditingController(text: s?.cfwNoAnswer ?? '');
    _voicemailCtrl = TextEditingController(text: s?.voicemailNumber ?? '');
    _provisioningUrlCtrl =
        TextEditingController(text: s?.provisioningUrl ?? '');
    _ntpServerCtrl = TextEditingController(text: s?.ntpServer ?? '');
    _timezoneCtrl = TextEditingController(text: s?.timezone ?? '');
    _buttonLayout = s?.buttonLayout?.map((k) => k.clone()).toList();
  }

  @override
  void dispose() {
    _sipServerCtrl.dispose();
    _sipPortCtrl.dispose();
    _regExpiryCtrl.dispose();
    _outboundProxyHostCtrl.dispose();
    _outboundProxyPortCtrl.dispose();
    _backupServerCtrl.dispose();
    _backupPortCtrl.dispose();
    _ringtoneCtrl.dispose();
    _screensaverTimeoutCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _voiceVlanCtrl.dispose();
    _dataVlanCtrl.dispose();
    _cfwAlwaysCtrl.dispose();
    _cfwBusyCtrl.dispose();
    _cfwNoAnswerCtrl.dispose();
    _voicemailCtrl.dispose();
    _provisioningUrlCtrl.dispose();
    _ntpServerCtrl.dispose();
    _timezoneCtrl.dispose();
    super.dispose();
  }

  String? _nonEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  DeviceSettings _buildSettings() => DeviceSettings(
        sipServer: _nonEmpty(_sipServerCtrl.text),
        sipPort: _nonEmpty(_sipPortCtrl.text),
        transport: _transport,
        regExpiry: _nonEmpty(_regExpiryCtrl.text),
        outboundProxyHost: _nonEmpty(_outboundProxyHostCtrl.text),
        outboundProxyPort: _nonEmpty(_outboundProxyPortCtrl.text),
        backupServer: _nonEmpty(_backupServerCtrl.text),
        backupPort: _nonEmpty(_backupPortCtrl.text),
        ringtone: _nonEmpty(_ringtoneCtrl.text),
        screensaverTimeout: _nonEmpty(_screensaverTimeoutCtrl.text),
        adminPassword: _nonEmpty(_adminPasswordCtrl.text),
        webUiEnabled: _webUiEnabled,
        voiceVlanId: _nonEmpty(_voiceVlanCtrl.text),
        dataVlanId: _nonEmpty(_dataVlanCtrl.text),
        cdpLldpEnabled: _cdpLldpEnabled,
        autoAnswer: _autoAnswer,
        autoAnswerMode: _autoAnswerMode,
        dndDefault: _dndDefault,
        callWaiting: _callWaiting,
        cfwAlways: _nonEmpty(_cfwAlwaysCtrl.text),
        cfwBusy: _nonEmpty(_cfwBusyCtrl.text),
        cfwNoAnswer: _nonEmpty(_cfwNoAnswerCtrl.text),
        voicemailNumber: _nonEmpty(_voicemailCtrl.text),
        provisioningUrl: _nonEmpty(_provisioningUrlCtrl.text),
        ntpServer: _nonEmpty(_ntpServerCtrl.text),
        timezone: _nonEmpty(_timezoneCtrl.text),
        buttonLayout: (_buttonLayout != null &&
                _buttonLayout!.any((k) => k.type != 'none'))
            ? _buttonLayout
            : null,
      );

  void _applyClone(DeviceSettings s) {
    setState(() {
      _sipServerCtrl.text = s.sipServer ?? '';
      _sipPortCtrl.text = s.sipPort ?? '';
      _transport = s.transport;
      _regExpiryCtrl.text = s.regExpiry ?? '';
      _outboundProxyHostCtrl.text = s.outboundProxyHost ?? '';
      _outboundProxyPortCtrl.text = s.outboundProxyPort ?? '';
      _backupServerCtrl.text = s.backupServer ?? '';
      _backupPortCtrl.text = s.backupPort ?? '';
      _ringtoneCtrl.text = s.ringtone ?? '';
      _screensaverTimeoutCtrl.text = s.screensaverTimeout ?? '';
      _adminPasswordCtrl.text = s.adminPassword ?? '';
      _webUiEnabled = s.webUiEnabled;
      _voiceVlanCtrl.text = s.voiceVlanId ?? '';
      _dataVlanCtrl.text = s.dataVlanId ?? '';
      _cdpLldpEnabled = s.cdpLldpEnabled;
      _autoAnswer = s.autoAnswer;
      _autoAnswerMode = s.autoAnswerMode;
      _dndDefault = s.dndDefault;
      _callWaiting = s.callWaiting;
      _cfwAlwaysCtrl.text = s.cfwAlways ?? '';
      _cfwBusyCtrl.text = s.cfwBusy ?? '';
      _cfwNoAnswerCtrl.text = s.cfwNoAnswer ?? '';
      _voicemailCtrl.text = s.voicemailNumber ?? '';
      _provisioningUrlCtrl.text = s.provisioningUrl ?? '';
      _ntpServerCtrl.text = s.ntpServer ?? '';
      _timezoneCtrl.text = s.timezone ?? '';
      _buttonLayout = s.buttonLayout?.map((k) => k.clone()).toList();
    });
  }

  Future<void> _showCloneDialog() async {
    if (widget.otherExtensions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other extensions to copy from')),
      );
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy From...'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.otherExtensions.length,
            itemBuilder: (_, i) {
              final info = widget.otherExtensions[i];
              return ListTile(
                dense: true,
                title:
                    Text('Ext ${info.extension}  —  ${info.label}'),
                trailing: info.settings != null
                    ? const Icon(Icons.settings,
                        size: 16, color: Colors.blue)
                    : const Text('no settings',
                        style: TextStyle(fontSize: 10, color: Colors.grey)),
                onTap: () => Navigator.pop(ctx, i),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      final info = widget.otherExtensions[selected];
      if (info.settings != null) {
        _applyClone(info.settings!.clone());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Copied settings from Ext ${info.extension} (${info.label})'),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Ext ${info.extension} has no custom settings to copy'),
        ));
      }
    }
  }

  /// Opens the wallpaper upload flow (pick image → resize → save).
  Future<void> _uploadWallpaper() async {
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text('Upload Wallpaper'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name (required)',
                  hintText: 'e.g. CompanyLogo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: selectedModel,
                isExpanded: true,
                items: DeviceTemplates.wallpaperSpecs.keys
                    .map((k) =>
                        DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setDS(() => selectedModel = v!),
              ),
              const SizedBox(height: 6),
              Text(
                'Required: '
                '${DeviceTemplates.getSpecForModel(selectedModel).width}×'
                '${DeviceTemplates.getSpecForModel(selectedModel).height} '
                '${DeviceTemplates.getSpecForModel(selectedModel).format.toUpperCase()}',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Pick & Upload'),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Enter a name first')));
                    return;
                  }
                  final res = await FilePicker.platform
                      .pickFiles(type: FileType.image);
                  if (res == null) return;
                  try {
                    final spec =
                        DeviceTemplates.getSpecForModel(selectedModel);
                    final filename =
                        await WallpaperService.processAndSaveWallpaper(
                            res.files.single.path!, spec, name);
                    final updated = await WallpaperService.listWallpapers();
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {
                      _wallpapers = updated;
                      _wallpaper = 'LOCAL:$filename';
                      _wallpaperChanged = true;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Wallpaper uploaded!')));
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Upload failed: $e')));
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }

  // ─── helpers ──────────────────────────────────────────────────────────────

  Widget _field(TextEditingController ctrl, String label,
      {String? hint,
      bool obscure = false,
      TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint ?? 'Inherited (global default)',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  /// A SwitchListTile that supports a tri-state: null (inherited), true, false.
  Widget _optSwitch(
      String title, bool? value, void Function(bool?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
          if (value == null)
            TextButton(
              onPressed: () => onChanged(false),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              child: const Text('Set', style: TextStyle(fontSize: 12)),
            )
          else ...[
            Switch(value: value, onChanged: onChanged),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Reset to inherited',
              onPressed: () => onChanged(null),
              visualDensity: VisualDensity.compact,
            ),
          ],
          if (value == null)
            const Text('Inherited',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Device Settings',
                style: TextStyle(fontSize: 16)),
            Text(
              'Ext ${widget.extension}  —  ${widget.label}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy From...',
            onPressed: _showCloneDialog,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: () => Navigator.pop(
              context,
              DeviceSettingsResult(
                settings: _buildSettings(),
                wallpaper: _wallpaperChanged ? _wallpaper : null,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── SIP & Registration ──────────────────────────────────────────
          ExpansionTile(
            leading: const Text('📞',
                style: TextStyle(fontSize: 20)),
            title: const Text('SIP & Registration'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _field(_sipServerCtrl, 'SIP Server Override'),
                    _field(_sipPortCtrl, 'SIP Port',
                        hint: '5060',
                        keyboard: TextInputType.number),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        value: _transport,
                        decoration: const InputDecoration(
                          labelText: 'Transport',
                          hintText: 'Inherited (UDP)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Inherited (UDP)')),
                          DropdownMenuItem(
                              value: 'UDP', child: Text('UDP')),
                          DropdownMenuItem(
                              value: 'TCP', child: Text('TCP')),
                          DropdownMenuItem(
                              value: 'TLS', child: Text('TLS')),
                          DropdownMenuItem(
                              value: 'DNS-SRV',
                              child: Text('DNS-SRV')),
                        ],
                        onChanged: (v) =>
                            setState(() => _transport = v),
                      ),
                    ),
                    _field(_regExpiryCtrl, 'Registration Expiry (s)',
                        hint: '3600',
                        keyboard: TextInputType.number),
                    _field(_outboundProxyHostCtrl,
                        'Outbound Proxy Host'),
                    _field(_outboundProxyPortCtrl,
                        'Outbound Proxy Port',
                        hint: '5060',
                        keyboard: TextInputType.number),
                    _field(_backupServerCtrl, 'Backup Server'),
                    _field(_backupPortCtrl, 'Backup Port',
                        hint: '5060',
                        keyboard: TextInputType.number),
                  ],
                ),
              ),
            ],
          ),

          // ── Display & Audio ─────────────────────────────────────────────
          ExpansionTile(
            leading: const Text('📱',
                style: TextStyle(fontSize: 20)),
            title: const Text('Display & Audio'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wallpaper picker + upload
                    const Text('Wallpaper',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: _wallpaper,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'Global Default',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null,
                                  child:
                                      Text('Global Default')),
                              ..._wallpapers.map((w) =>
                                  DropdownMenuItem<String?>(
                                    value: 'LOCAL:${w.filename}',
                                    child: Text(w.name,
                                        overflow:
                                            TextOverflow
                                                .ellipsis),
                                  )),
                            ],
                            onChanged: (v) => setState(() {
                              _wallpaper = v;
                              _wallpaperChanged = true;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.upload),
                          tooltip: 'Upload new wallpaper',
                          onPressed: _uploadWallpaper,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(_ringtoneCtrl, 'Ringtone',
                        hint: 'e.g. Ring1.wav'),
                    _field(_screensaverTimeoutCtrl,
                        'Screensaver Timeout (s)',
                        keyboard: TextInputType.number),
                  ],
                ),
              ),
            ],
          ),

          // ── Security ────────────────────────────────────────────────────
          ExpansionTile(
            leading: const Text('🔑',
                style: TextStyle(fontSize: 20)),
            title: const Text('Security'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _field(_adminPasswordCtrl,
                        'Admin Password Override',
                        obscure: true),
                    _optSwitch(
                        'Web UI Access',
                        _webUiEnabled,
                        (v) =>
                            setState(() => _webUiEnabled = v)),
                  ],
                ),
              ),
            ],
          ),

          // ── Network ─────────────────────────────────────────────────────
          ExpansionTile(
            leading: const Text('🌐',
                style: TextStyle(fontSize: 20)),
            title: const Text('Network'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _field(_voiceVlanCtrl, 'Voice VLAN ID',
                        keyboard: TextInputType.number),
                    _field(_dataVlanCtrl, 'Data VLAN ID',
                        keyboard: TextInputType.number),
                    _optSwitch(
                        'CDP / LLDP',
                        _cdpLldpEnabled,
                        (v) => setState(
                            () => _cdpLldpEnabled = v)),
                  ],
                ),
              ),
            ],
          ),

          // ── Call Features ───────────────────────────────────────────────
          ExpansionTile(
            leading: const Text('📲',
                style: TextStyle(fontSize: 20)),
            title: const Text('Call Features'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _optSwitch(
                        'Auto Answer',
                        _autoAnswer,
                        (v) =>
                            setState(() => _autoAnswer = v)),
                    if (_autoAnswer == true)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String?>(
                          value: _autoAnswerMode,
                          decoration: const InputDecoration(
                            labelText: 'Auto Answer Mode',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Default')),
                            DropdownMenuItem(
                                value: 'on',
                                child: Text('Always On')),
                            DropdownMenuItem(
                                value: 'intercom-only',
                                child:
                                    Text('Intercom Only')),
                          ],
                          onChanged: (v) => setState(
                              () => _autoAnswerMode = v),
                        ),
                      ),
                    _optSwitch(
                        'Do Not Disturb (default on)',
                        _dndDefault,
                        (v) =>
                            setState(() => _dndDefault = v)),
                    _optSwitch(
                        'Call Waiting',
                        _callWaiting,
                        (v) =>
                            setState(() => _callWaiting = v)),
                    _field(_cfwAlwaysCtrl,
                        'Call Forward Always',
                        hint: 'e.g. +61400000000'),
                    _field(_cfwBusyCtrl, 'Call Forward Busy'),
                    _field(_cfwNoAnswerCtrl,
                        'Call Forward No Answer'),
                    _field(_voicemailCtrl, 'Voicemail Number'),
                  ],
                ),
              ),
            ],
          ),

          // ── Provisioning ────────────────────────────────────────────────
          ExpansionTile(
            leading: const Text('🔧',
                style: TextStyle(fontSize: 20)),
            title: const Text('Provisioning'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _field(_provisioningUrlCtrl,
                        'Provisioning URL Override',
                        hint: 'Inherited from server settings'),
                    _field(_ntpServerCtrl, 'NTP Server',
                        hint: 'e.g. pool.ntp.org'),
                    _field(_timezoneCtrl, 'Timezone',
                        hint: 'e.g. +10'),
                  ],
                ),
              ),
            ],
          ),

          // ── Button Layout ────────────────────────────────────────────────
          _buildButtonLayoutTile(),
        ],
      ),
    );
  }

  Widget _buildButtonLayoutTile() {
    final programmed = _buttonLayout
            ?.where((k) => k.type != 'none')
            .length ??
        0;
    final total = _buttonLayout?.length ?? 0;
    final subtitle = total > 0
        ? '$programmed / $total buttons programmed'
        : 'Using model default';

    return Card(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      child: ListTile(
        leading: const Text('🎹',
            style: TextStyle(fontSize: 24)),
        title: const Text('Button Layout'),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () async {
          final batchExts = widget.otherExtensions
              .map((e) =>
                  (extension: e.extension, label: e.label))
              .toList();

          final result =
              await Navigator.push<List<ButtonKey>>(
            context,
            MaterialPageRoute(
              builder: (_) => PerExtensionButtonEditorScreen(
                extension: widget.extension,
                label: widget.label,
                model: widget.model,
                initialLayout: _buttonLayout,
                batchExtensions: batchExts,
              ),
            ),
          );
          if (result != null) {
            setState(() => _buttonLayout = result);
          }
        },
      ),
    );
  }
}
