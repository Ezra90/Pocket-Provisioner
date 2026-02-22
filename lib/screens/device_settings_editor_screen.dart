import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../data/device_templates.dart';
import '../models/button_key.dart';
import '../models/device_settings.dart';
import '../services/mustache_renderer.dart';
import '../services/ringtone_service.dart';
import '../services/wallpaper_service.dart';
import 'per_extension_button_editor.dart';

/// Info about another extension, used in the Copy From... dialog.
typedef ExtensionCloneInfo = ({
  String extension,
  String label,
  DeviceSettings? settings,
  /// Per-device wallpaper value (e.g. 'LOCAL:file.png'), or null if unset.
  String? wallpaper,
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
  String? _ringtone;
  List<RingtoneInfo> _ringtones = [];
  late final TextEditingController _screensaverTimeoutCtrl;

  // Template capability flags (null = still loading)
  Set<String>? _templateTags;

  /// Returns true when the loaded template contains [tag] (or while still
  /// loading — fail-open so fields are not permanently hidden).
  bool _templateSupports(String tag) =>
      _templateTags == null || _templateTags!.contains(tag);

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
  late final TextEditingController _dstEnableCtrl;

  // Diagnostics
  late final TextEditingController _syslogServerCtrl;
  late final TextEditingController _debugLevelCtrl;

  // Call Features (extended)
  late final TextEditingController _dialPlanCtrl;

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
    _ringtone = s?.ringtone;
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
    _dstEnableCtrl = TextEditingController(text: s?.dstEnable ?? '');
    _syslogServerCtrl = TextEditingController(text: s?.syslogServer ?? '');
    _debugLevelCtrl = TextEditingController(text: s?.debugLevel ?? '');
    _dialPlanCtrl = TextEditingController(text: s?.dialPlan ?? '');
    _buttonLayout = s?.buttonLayout?.map((k) => k.clone()).toList();
    RingtoneService.listRingtones().then((list) {
      if (mounted) setState(() => _ringtones = list);
    });
    MustacheRenderer.resolveTemplateKey(widget.model).then((templateKey) {
      MustacheRenderer.extractAllTags(templateKey).then((tags) {
        if (mounted) setState(() => _templateTags = tags);
      });
    });
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
    _dstEnableCtrl.dispose();
    _syslogServerCtrl.dispose();
    _debugLevelCtrl.dispose();
    _dialPlanCtrl.dispose();
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
        ringtone: _ringtone?.isNotEmpty == true ? _ringtone : null,
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
        dialPlan: _nonEmpty(_dialPlanCtrl.text),
        provisioningUrl: _nonEmpty(_provisioningUrlCtrl.text),
        ntpServer: _nonEmpty(_ntpServerCtrl.text),
        timezone: _nonEmpty(_timezoneCtrl.text),
        dstEnable: _nonEmpty(_dstEnableCtrl.text),
        syslogServer: _nonEmpty(_syslogServerCtrl.text),
        debugLevel: _nonEmpty(_debugLevelCtrl.text),
        buttonLayout: _buttonLayout,
      );

  void _applyClone(DeviceSettings s, {String? wallpaper}) {
    setState(() {
      _sipServerCtrl.text = s.sipServer ?? '';
      _sipPortCtrl.text = s.sipPort ?? '';
      _transport = s.transport;
      _regExpiryCtrl.text = s.regExpiry ?? '';
      _outboundProxyHostCtrl.text = s.outboundProxyHost ?? '';
      _outboundProxyPortCtrl.text = s.outboundProxyPort ?? '';
      _backupServerCtrl.text = s.backupServer ?? '';
      _backupPortCtrl.text = s.backupPort ?? '';
      _ringtone = s.ringtone;
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
      _dialPlanCtrl.text = s.dialPlan ?? '';
      _provisioningUrlCtrl.text = s.provisioningUrl ?? '';
      _ntpServerCtrl.text = s.ntpServer ?? '';
      _timezoneCtrl.text = s.timezone ?? '';
      _dstEnableCtrl.text = s.dstEnable ?? '';
      _syslogServerCtrl.text = s.syslogServer ?? '';
      _debugLevelCtrl.text = s.debugLevel ?? '';
      _buttonLayout = s.buttonLayout?.map((k) => k.clone()).toList();
      // Always apply the cloned wallpaper state, even if null
      _wallpaper = wallpaper;
      _wallpaperChanged = true;
    });
  }

  /// Returns the number of programmed buttons in [settings], or 0.
  static int _programmedButtonCount(DeviceSettings? settings) =>
      settings?.buttonLayout?.where((k) => k.type != 'none').length ?? 0;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copies all settings and button layout.\n'
                'Extension number, SIP username and password\n'
                'are never copied.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.otherExtensions.length,
                  itemBuilder: (_, i) {
                    final info = widget.otherExtensions[i];
                    final s = info.settings;
                    final hasSettings = s != null;
                    final buttonCount = _programmedButtonCount(s);
                    final hasWallpaper = info.wallpaper != null &&
                        info.wallpaper!.isNotEmpty;
                    final hasCopyableData = hasSettings || hasWallpaper;

                    return ListTile(
                      dense: true,
                      title: Text(
                        'Ext ${info.extension}  —  ${info.label}',
                        style: TextStyle(
                          color: hasCopyableData ? null : Colors.grey,
                        ),
                      ),
                      subtitle: _buildCopyFromSubtitle(
                        hasSettings: hasSettings,
                        buttonCount: buttonCount,
                        hasWallpaper: hasWallpaper,
                        hasRingtone: s?.ringtone != null,
                      ),
                      onTap: () => Navigator.pop(ctx, i),
                    );
                  },
                ),
              ),
            ],
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

    if (selected == null || !mounted) return;

    final info = widget.otherExtensions[selected];
    final hasSettings = info.settings != null;
    final hasWallpaper =
        info.wallpaper != null && info.wallpaper!.isNotEmpty;

    if (!hasSettings && !hasWallpaper) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Ext ${info.extension} has no settings or wallpaper to copy'),
      ));
      return;
    }

    // Apply — settings first (blanks fields when null), then wallpaper.
    _applyClone(
      info.settings?.clone() ?? DeviceSettings(),
      wallpaper: info.wallpaper,
    );

    // Build an informative confirmation.
    final btnCount = _programmedButtonCount(info.settings);
    final parts = <String>[];
    if (hasSettings) {
      parts.add('settings');
      if (btnCount > 0) parts.add('$btnCount button${btnCount == 1 ? '' : 's'}');
      if (info.settings!.ringtone != null) parts.add('ringtone');
    }
    if (hasWallpaper) parts.add('wallpaper');

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Copied ${parts.join(', ')} from Ext ${info.extension} '
        '(${info.label}) — review and save',
      ),
    ));
  }

  /// Builds the small capability-chips row shown under each extension in
  /// the Copy From list.
  Widget? _buildCopyFromSubtitle({
    required bool hasSettings,
    required int buttonCount,
    required bool hasWallpaper,
    required bool hasRingtone,
  }) {
    final chips = <Widget>[];
    if (hasSettings) {
      chips.add(_chip(Icons.settings, 'Settings', Colors.blue));
    }
    if (buttonCount > 0) {
      chips.add(_chip(Icons.keyboard, '$buttonCount buttons', Colors.green));
    }
    if (hasWallpaper) {
      chips.add(_chip(Icons.image, 'Wallpaper', Colors.orange));
    }
    if (hasRingtone) {
      chips.add(_chip(Icons.music_note, 'Ringtone', Colors.purple));
    }
    if (chips.isEmpty) {
      return const Text(
        'Nothing to copy',
        style: TextStyle(fontSize: 10, color: Colors.grey),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(spacing: 4, runSpacing: 2, children: chips),
    );
  }

  static Widget _chip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color),
          ),
          const SizedBox(width: 6),
        ],
      );

  /// Opens the wallpaper upload flow (pick image → resize → save).
  Future<void> _uploadWallpaper() async {
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text('Upload Wallpaper'),
          content: SingleChildScrollView(
            child: Column(
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

  /// Opens the ringtone upload flow (pick audio → convert → save).
  Future<void> _uploadRingtone() async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Ringtone'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name (required)',
                  hintText: 'e.g. MyRingtone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Accepts MP3, WAV, M4A, OGG, etc.\nAuto-converted to 8kHz/16-bit/mono WAV.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.audio_file),
                label: const Text('Pick & Upload'),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a name first')));
                    return;
                  }
                  final res = await FilePicker.platform
                      .pickFiles(type: FileType.audio);
                  if (res == null) return;
                  try {
                    final filename = await RingtoneService.convertAndSave(
                        res.files.single.path!, name);
                    final updated = await RingtoneService.listRingtones();
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {
                      _ringtones = updated;
                      _ringtone = 'LOCAL:$filename';
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Ringtone uploaded!')));
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
  }

  Widget _field(TextEditingController ctrl, String label,
      {String? hint,
      bool obscure = false,
      TextInputType? keyboard,
      List<TextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
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
                wallpaper: _wallpaperChanged ? (_wallpaper ?? '') : null,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
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
                        isExpanded: true,
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
                    // Wallpaper picker — only shown if template uses wallpaper_url
                    if (_templateSupports('wallpaper_url')) ...[
                      const Text('Wallpaper',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _wallpaper,
                              isExpanded: true,
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
                    ],

                    // Ringtone picker — only shown if template uses ring_type
                    if (_templateSupports('ring_type') ||
                        _templateSupports('ringtone_url')) ...[
                      const Text('Ringtone',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _ringtone,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                hintText: 'Default (Ring1.wav)',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(
                                        'Default (Ring1.wav)')),
                                ..._ringtones.map((r) =>
                                    DropdownMenuItem<String?>(
                                      value: 'LOCAL:${r.filename}',
                                      child: Text(r.name,
                                          overflow:
                                              TextOverflow
                                                  .ellipsis),
                                    )),
                              ],
                              onChanged: (v) =>
                                  setState(() => _ringtone = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.upload),
                            tooltip: 'Upload new ringtone',
                            onPressed: _uploadRingtone,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

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
                    // VLAN — only shown if template uses vlan_enabled
                    if (_templateSupports('vlan_enabled') ||
                        _templateSupports('voice_vlan_id')) ...[
                      _field(_voiceVlanCtrl, 'Voice VLAN ID',
                          keyboard: TextInputType.number),
                      _field(_dataVlanCtrl, 'Data VLAN ID',
                          keyboard: TextInputType.number),
                    ],
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
                          isExpanded: true,
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
                    _field(_dialPlanCtrl, 'Dial Plan',
                        hint: 'e.g. (x+|\\+x+|xxx|xx+)',
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'"')),
                        ]),
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        value: _dstEnableCtrl.text.isEmpty ? null : _dstEnableCtrl.text,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Daylight Savings Time',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('Inherited (Global Default)')),
                          DropdownMenuItem(value: '0', child: Text('Disabled (0)')),
                          DropdownMenuItem(value: '1', child: Text('Automatic (1)')),
                          DropdownMenuItem(value: '2', child: Text('Manual (2)')),
                        ],
                        onChanged: (v) => setState(() => _dstEnableCtrl.text = v ?? ''),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Diagnostics ─────────────────────────────────────────────────
          ExpansionTile(
            leading: const Text('🔍',
                style: TextStyle(fontSize: 20)),
            title: const Text('Diagnostics & Logs'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _field(_syslogServerCtrl, 'Syslog Server',
                        hint: 'e.g. 192.168.1.100'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        value: _debugLevelCtrl.text.isEmpty ? null : _debugLevelCtrl.text,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Debug Level',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('Inherited (Global Default)')),
                          DropdownMenuItem(value: '0', child: Text('Off (0)')),
                          DropdownMenuItem(value: '1', child: Text('Low (1)')),
                          DropdownMenuItem(value: '2', child: Text('Medium (2)')),
                          DropdownMenuItem(value: '3', child: Text('Verbose (3)')),
                        ],
                        onChanged: (v) => setState(() => _debugLevelCtrl.text = v ?? ''),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Button Layout — only shown if template uses line_keys ────────
          if (_templateSupports('line_keys'))
            _buildButtonLayoutTile(),
        ],
        ),
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
