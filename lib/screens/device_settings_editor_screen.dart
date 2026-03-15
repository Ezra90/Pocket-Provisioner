import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../data/device_templates.dart';
import '../models/button_key.dart';
import '../models/device_settings.dart';
import '../models/phonebook_entry.dart';
import '../services/global_settings.dart';
import '../services/mustache_renderer.dart';
import '../services/template_metadata_parser.dart';
import '../services/ringtone_service.dart';
import '../services/wallpaper_service.dart';
import '../services/firmware_service.dart';
import 'per_extension_button_editor.dart';
import 'per_extension_phonebook_editor.dart';

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
  
  // Line-level overrides
  late final TextEditingController _extensionOverrideCtrl;
  late final TextEditingController _passwordOverrideCtrl;
  late final TextEditingController _displayNameOverrideCtrl;
  late final TextEditingController _authUsernameOverrideCtrl;
  bool _showPasswordOverride = false;

  // Display & Audio
  String? _wallpaper;
  bool _wallpaperChanged = false;
  late List<WallpaperInfo> _wallpapers;
  String? _ringtone;
  List<RingtoneInfo> _ringtones = [];
  late final TextEditingController _screensaverTimeoutCtrl;

  // Template capability flags (null = still loading)
  Set<String>? _templateTags;

  // Template metadata for showing variable descriptions/examples in the UI.
  TemplateMetadata? _templateMeta;

  /// Returns true when the loaded template contains [tag] (or while still
  /// loading — fail-open so fields are not permanently hidden).
  bool _templateSupports(String tag) =>
      _templateTags == null || _templateTags!.contains(tag);

  /// Returns a helper text string for a template variable (description + example).
  String? _varHelper(String varName) {
    final meta = _templateMeta?.variables[varName];
    if (meta == null) return null;
    final desc = meta.description;
    final example = meta.example;
    if (desc.isEmpty && example.isEmpty) return null;
    if (example.isEmpty) return desc;
    return '$desc (e.g. $example)';
  }

  // Security
  late final TextEditingController _adminPasswordCtrl;
  bool? _webUiEnabled;
  bool _showAdminPassword = false;

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
  /// Holds the "LOCAL:<filename>" value when a server-hosted file is selected.
  String? _firmwareLocalFile;
  /// Holds a custom direct URL when the user types one manually.
  late final TextEditingController _firmwareCustomUrlCtrl;
  List<FirmwareInfo> _firmwareFiles = [];
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

  // Phonebook
  List<PhonebookEntry>? _phonebookEntries;

  // Global mode (loaded for hints)
  String _globalMode = GlobalSettings.modeDms;

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
    // Line-level overrides
    _extensionOverrideCtrl = TextEditingController(text: s?.extensionOverride ?? '');
    _passwordOverrideCtrl = TextEditingController(text: s?.passwordOverride ?? '');
    _displayNameOverrideCtrl = TextEditingController(text: s?.displayNameOverride ?? '');
    _authUsernameOverrideCtrl = TextEditingController(text: s?.authUsernameOverride ?? '');
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
    // Initialise controller first, then populate via helper to avoid duplication
    _firmwareCustomUrlCtrl = TextEditingController();
    _applyFirmwareUrl(s?.firmwareUrl);
    _ntpServerCtrl = TextEditingController(text: s?.ntpServer ?? '');
    _timezoneCtrl = TextEditingController(text: s?.timezone ?? '');
    _dstEnableCtrl = TextEditingController(text: s?.dstEnable ?? '');
    _syslogServerCtrl = TextEditingController(text: s?.syslogServer ?? '');
    _debugLevelCtrl = TextEditingController(text: s?.debugLevel ?? '');
    _dialPlanCtrl = TextEditingController(text: s?.dialPlan ?? '');
    _buttonLayout = s?.buttonLayout?.map((k) => k.clone()).toList();
    _phonebookEntries = s?.phonebookEntries?.map((e) => e.clone()).toList();
    RingtoneService.listRingtones().then((list) {
      if (mounted) setState(() => _ringtones = list);
    });
    FirmwareService.listFirmware().then((list) {
      if (mounted) setState(() => _firmwareFiles = list);
    });
    MustacheRenderer.resolveTemplateKey(widget.model).then((templateKey) {
      MustacheRenderer.extractAllTags(templateKey).then((tags) {
        if (mounted) setState(() => _templateTags = tags);
      });
      TemplateMetadataParser.parse(templateKey).then((meta) {
        if (mounted) setState(() => _templateMeta = meta);
      });
    });
    GlobalSettings.getMode().then((mode) {
      if (mounted) setState(() => _globalMode = mode);
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
    _extensionOverrideCtrl.dispose();
    _passwordOverrideCtrl.dispose();
    _displayNameOverrideCtrl.dispose();
    _authUsernameOverrideCtrl.dispose();
    _screensaverTimeoutCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _voiceVlanCtrl.dispose();
    _dataVlanCtrl.dispose();
    _cfwAlwaysCtrl.dispose();
    _cfwBusyCtrl.dispose();
    _cfwNoAnswerCtrl.dispose();
    _voicemailCtrl.dispose();
    _provisioningUrlCtrl.dispose();
    _firmwareCustomUrlCtrl.dispose();
    _ntpServerCtrl.dispose();
    _timezoneCtrl.dispose();
    _dstEnableCtrl.dispose();
    _syslogServerCtrl.dispose();
    _debugLevelCtrl.dispose();
    _dialPlanCtrl.dispose();
    super.dispose();
  }

  String? _nonEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  /// Splits [rawFw] into (_firmwareLocalFile, customUrl) and applies both.
  /// A `LOCAL:` prefixed value goes to the dropdown; anything else to the text field.
  void _applyFirmwareUrl(String? rawFw) {
    if (rawFw != null && rawFw.startsWith('LOCAL:')) {
      _firmwareLocalFile = rawFw;
      _firmwareCustomUrlCtrl.clear();
    } else {
      _firmwareLocalFile = null;
      _firmwareCustomUrlCtrl.text = rawFw ?? '';
    }
  }

  DeviceSettings _buildSettings() => DeviceSettings(
        sipServer: _nonEmpty(_sipServerCtrl.text),
        sipPort: _nonEmpty(_sipPortCtrl.text),
        transport: _transport,
        regExpiry: _nonEmpty(_regExpiryCtrl.text),
        outboundProxyHost: _nonEmpty(_outboundProxyHostCtrl.text),
        outboundProxyPort: _nonEmpty(_outboundProxyPortCtrl.text),
        backupServer: _nonEmpty(_backupServerCtrl.text),
        backupPort: _nonEmpty(_backupPortCtrl.text),
        extensionOverride: _nonEmpty(_extensionOverrideCtrl.text),
        passwordOverride: _nonEmpty(_passwordOverrideCtrl.text),
        displayNameOverride: _nonEmpty(_displayNameOverrideCtrl.text),
        authUsernameOverride: _nonEmpty(_authUsernameOverrideCtrl.text),
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
        firmwareUrl: _firmwareLocalFile ?? _nonEmpty(_firmwareCustomUrlCtrl.text),
        ntpServer: _nonEmpty(_ntpServerCtrl.text),
        timezone: _nonEmpty(_timezoneCtrl.text),
        dstEnable: _nonEmpty(_dstEnableCtrl.text),
        syslogServer: _nonEmpty(_syslogServerCtrl.text),
        debugLevel: _nonEmpty(_debugLevelCtrl.text),
        buttonLayout: _buttonLayout,
        phonebookEntries: _phonebookEntries,
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
      // Note: Don't clone line-level overrides (extension, password, display name, auth username)
      // as these are unique to each device
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
      _applyFirmwareUrl(s.firmwareUrl);
      _ntpServerCtrl.text = s.ntpServer ?? '';
      _timezoneCtrl.text = s.timezone ?? '';
      _dstEnableCtrl.text = s.dstEnable ?? '';
      _syslogServerCtrl.text = s.syslogServer ?? '';
      _debugLevelCtrl.text = s.debugLevel ?? '';
      _buttonLayout = s.buttonLayout?.map((k) => k.clone()).toList();
      _phonebookEntries = s.phonebookEntries?.map((e) => e.clone()).toList();
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
    String selectedModel =
        DeviceTemplates.getWallpaperSpecKeyForDeviceModel(widget.model);
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
                    if (mounted) {
                      setState(() {
                        _wallpapers = updated;
                        _wallpaper = 'LOCAL:$filename';
                        _wallpaperChanged = true;
                      });
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
                'WAV files only (max 1 MB).\n'
                'Stereo files are auto-converted to mono.\n'
                'Recommended: PCM, 8 kHz, 16-bit, Mono.',
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
                  final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom, allowedExtensions: ['wav']);
                  if (res == null) return;
                  try {
                    final saved = await RingtoneService.convertAndSave(
                        res.files.single.path!, name);
                    final updated = await RingtoneService.listRingtones();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      setState(() {
                        _ringtones = updated;
                        _ringtone = 'LOCAL:${saved.filename}';
                      });
                      final info = saved.wavInfo;
                      final note = info?.compatibilityNote;
                      final msg = note != null
                          ? 'Uploaded (${info!.formatString}) — ⚠ $note'
                          : info != null
                              ? 'Uploaded — ${info.formatString}'
                              : 'Ringtone uploaded!';
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 5)));
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

  /// Upload a firmware file to the server's firmware directory.
  Future<void> _uploadFirmwareFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final sourcePath = file.path;
    if (sourcePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access selected file')),
        );
      }
      return;
    }

    try {
      final saved = await FirmwareService.copyFirmware(sourcePath, file.name);
      final updated = await FirmwareService.listFirmware();
      if (mounted) {
        setState(() {
          _firmwareFiles = updated;
          _firmwareLocalFile = 'LOCAL:${saved.filename}';
          _firmwareCustomUrlCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded: ${saved.filename}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Widget _field(TextEditingController ctrl, String label,
      {String? hint,
      bool obscure = false,
      bool? showPassword,
      VoidCallback? onTogglePassword,
      TextInputType? keyboard,
      List<TextInputFormatter>? inputFormatters,
      String? varName}) {
    final helperText = varName != null ? _varHelper(varName) : null;
    final isObscured = obscure && !(showPassword ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: isObscured,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint ?? 'Default (from global settings)',
          helperText: helperText,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: obscure && onTogglePassword != null
              ? IconButton(
                  icon: Icon(
                    isObscured ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  tooltip: isObscured ? 'Show password' : 'Hide password',
                  onPressed: onTogglePassword,
                )
              : null,
        ),
      ),
    );
  }

  /// A SwitchListTile that supports a tri-state: null (default), true, false.
  /// When [subtitle] is provided it is shown below the title for extra context.
  Widget _optSwitch(
      String title, bool? value, void Function(bool?) onChanged,
      {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  tooltip: 'Reset to default',
                  onPressed: () => onChanged(null),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (value == null)
                const Text('Default',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
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
                    // Line-level overrides section
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Line Configuration Overrides',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Override the extension, password, or display name from the CSV import. '
                            'Leave blank to use the original values (Ext ${widget.extension}).',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          _field(_extensionOverrideCtrl, 'Extension / Username Override',
                              hint: 'Default: ${widget.extension}'),
                          _field(_passwordOverrideCtrl, 'SIP Password Override',
                              hint: 'Default: (from import)',
                              obscure: true,
                              showPassword: _showPasswordOverride,
                              onTogglePassword: () => setState(
                                  () => _showPasswordOverride = !_showPasswordOverride)),
                          _field(_displayNameOverrideCtrl, 'Display Name Override',
                              hint: 'Default: ${widget.label.isNotEmpty ? widget.label : widget.extension}'),
                          _field(_authUsernameOverrideCtrl, 'Auth Username Override',
                              hint: 'Default: same as extension'),
                        ],
                      ),
                    ),
                    _field(_sipServerCtrl,
                        _globalMode == GlobalSettings.modeDms
                            ? 'SIP Server Override (DMS mode: leave blank)'
                            : 'SIP Server Override',
                        hint: _globalMode == GlobalSettings.modeDms
                            ? 'Default from DMS – blank for most jobs'
                            : 'Default (from global settings)',
                        varName: 'sip_server'),
                    _field(_sipPortCtrl, 'SIP Port',
                        hint: '5060',
                        keyboard: TextInputType.number,
                        varName: 'sip_port'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        value: _transport,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Transport',
                          hintText: 'Default (UDP)',
                          helperText: _varHelper('transport'),
                          helperMaxLines: 2,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Default (UDP)')),
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
                        keyboard: TextInputType.number,
                        varName: 'reg_expiry'),
                    _field(_outboundProxyHostCtrl,
                        'Outbound Proxy Host',
                        varName: 'outbound_proxy_host'),
                    _field(_outboundProxyPortCtrl,
                        'Outbound Proxy Port',
                        hint: '5060',
                        keyboard: TextInputType.number,
                        varName: 'outbound_proxy_port'),
                    _field(_backupServerCtrl, 'Backup Server',
                        varName: 'backup_server'),
                    _field(_backupPortCtrl, 'Backup Port',
                        hint: '5060',
                        keyboard: TextInputType.number,
                        varName: 'backup_port'),
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
                        keyboard: TextInputType.number,
                        varName: 'screensaver_timeout'),
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
                        obscure: true,
                        showPassword: _showAdminPassword,
                        onTogglePassword: () => setState(
                            () => _showAdminPassword = !_showAdminPassword),
                        varName: 'admin_password'),
                    _optSwitch(
                        'Web UI Access',
                        _webUiEnabled,
                        (v) =>
                            setState(() => _webUiEnabled = v),
                        subtitle: 'Enable or disable the phone\'s built-in web management interface'),
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
                          keyboard: TextInputType.number,
                          varName: 'voice_vlan_id'),
                      _field(_dataVlanCtrl, 'Data VLAN ID',
                          keyboard: TextInputType.number,
                          varName: 'data_vlan_id'),
                    ],
                    _optSwitch(
                        'CDP / LLDP',
                        _cdpLldpEnabled,
                        (v) => setState(
                            () => _cdpLldpEnabled = v),
                        subtitle: 'Cisco Discovery Protocol / Link Layer Discovery Protocol — '
                            'auto-discovers VLAN and network policy from the switch. '
                            'Enable if your network switch broadcasts VLAN tags via CDP or LLDP'),
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
                            setState(() => _autoAnswer = v),
                        subtitle: 'Automatically answer incoming calls (useful for intercom/paging)'),
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
                            setState(() => _dndDefault = v),
                        subtitle: 'When enabled, the phone rejects all incoming calls by default'),
                    _optSwitch(
                        'Call Waiting',
                        _callWaiting,
                        (v) =>
                            setState(() => _callWaiting = v),
                        subtitle: 'Allow a second incoming call while already on a call'),
                    _field(_cfwAlwaysCtrl,
                        'Call Forward Always',
                        hint: 'e.g. +61400000000',
                        varName: 'cfw_always'),
                    _field(_cfwBusyCtrl, 'Call Forward Busy',
                        varName: 'cfw_busy'),
                    _field(_cfwNoAnswerCtrl,
                        'Call Forward No Answer',
                        varName: 'cfw_no_answer'),
                    _field(_voicemailCtrl, 'Voicemail Number',
                        varName: 'voicemail_number'),
                    _field(_dialPlanCtrl, 'Dial Plan',
                        hint: 'e.g. (x+|\\+x+|xxx|xx+)',
                        varName: 'dial_plan',
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
                        _globalMode == GlobalSettings.modeDms
                            ? 'Target DMS / EPM URL Override'
                            : 'Provisioning URL Override',
                        hint: _globalMode == GlobalSettings.modeDms
                            ? 'Default (from Global Settings DMS URL)'
                            : 'Default (from server settings)',
                        varName: 'provisioning_url'),
                    // ── Firmware Upgrade URL ──────────────────────────────
                    if (_templateSupports('firmware_url')) ...[
                      const Text('Firmware Upgrade',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      // ① Pick a server-hosted file
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _firmwareLocalFile,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Server-hosted file',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('None (no firmware push)')),
                                ..._firmwareFiles.map((f) =>
                                    DropdownMenuItem<String?>(
                                      value: 'LOCAL:${f.filename}',
                                      child: Text(f.filename,
                                          overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (v) => setState(() {
                                _firmwareLocalFile = v;
                                // Clear custom URL so only one source is active
                                _firmwareCustomUrlCtrl.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.upload_file),
                            tooltip: 'Upload firmware file',
                            onPressed: _uploadFirmwareFile,
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('or', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                          Expanded(child: Divider()),
                        ]),
                      ),
                      // ② Enter a direct URL
                      TextField(
                        controller: _firmwareCustomUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Custom firmware URL',
                          hintText: 'http://server/firmware/T54W.rom',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() {
                          // Clear dropdown so only one source is active
                          if (v.isNotEmpty) _firmwareLocalFile = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _field(_ntpServerCtrl, 'NTP Server',
                        hint: 'e.g. pool.ntp.org',
                        varName: 'ntp_server'),
                    _field(_timezoneCtrl, 'Timezone',
                        hint: 'e.g. +10',
                        varName: 'timezone'),
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
                        hint: 'e.g. 192.168.1.100',
                        varName: 'syslog_server'),
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
          // ── Phonebook ─────────────────────────────────────────────────────
          _buildPhonebookTile(),
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

  Widget _buildPhonebookTile() {
    final count = _phonebookEntries?.length ?? 0;
    final subtitle =
        count > 0 ? '$count contact${count == 1 ? '' : 's'}' : 'No contacts';

    return Card(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      child: ListTile(
        leading: const Text('📒',
            style: TextStyle(fontSize: 24)),
        title: const Text('Phonebook'),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () async {
          final batchExts = widget.otherExtensions
              .map((e) => (extension: e.extension, label: e.label))
              .toList();

          final result = await Navigator.push<List<PhonebookEntry>>(
            context,
            MaterialPageRoute(
              builder: (_) => PerExtensionPhonebookEditorScreen(
                extension: widget.extension,
                label: widget.label,
                model: widget.model,
                initialEntries: _phonebookEntries,
                batchExtensions: batchExts,
              ),
            ),
          );
          if (result != null) {
            setState(() =>
                _phonebookEntries = result.isEmpty ? null : result);
          }
        },
      ),
    );
  }
}
