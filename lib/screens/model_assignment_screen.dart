import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';
import '../models/device_settings.dart';
import '../services/wallpaper_service.dart';
import 'device_settings_editor_screen.dart';

/// Intermediate review screen shown after CSV parsing.
/// Allows per-device model, wallpaper, MAC and settings assignment before
/// committing to the DB.
class ModelAssignmentScreen extends StatefulWidget {
  final List<Device> devices;

  /// Default model to use for rows whose CSV model is unrecognised.
  final String? defaultModel;

  const ModelAssignmentScreen(
      {super.key, required this.devices, this.defaultModel});

  @override
  State<ModelAssignmentScreen> createState() => _ModelAssignmentScreenState();
}

class _ModelAssignmentScreenState extends State<ModelAssignmentScreen> {
  late List<_RowState> _rows;
  List<WallpaperInfo> _wallpapers = [];

  /// All MACs available for assignment (from CSV + scanned during review).
  List<String> _scannedMacs = [];

  bool get _allSelected =>
      _rows.isNotEmpty && _rows.every((r) => r.selected);
  bool get _anySelected => _rows.any((r) => r.selected);

  @override
  void initState() {
    super.initState();
    _rows = widget.devices
        .map((d) => _RowState(device: d, defaultModel: widget.defaultModel))
        .toList();
    // Pre-populate MAC pool with any MACs that came from the CSV.
    _scannedMacs = _rows
        .where((r) => r.macAddress != null)
        .map((r) => r.macAddress!)
        .toSet()
        .toList();
    _loadWallpapers();
  }

  Future<void> _loadWallpapers() async {
    final wallpapers = await WallpaperService.listWallpapers();
    if (mounted) setState(() => _wallpapers = wallpapers);
  }

  // ── selection helpers ────────────────────────────────────────────────────

  void _toggleAll(bool? value) {
    final checked = value ?? false;
    setState(() {
      for (final row in _rows) {
        row.selected = checked;
      }
    });
  }

  // ── MAC helpers ──────────────────────────────────────────────────────────

  /// Format a raw 12-char hex MAC into AA:BB:CC:DD:EE:FF.
  static String _formatMac(String mac) {
    final clean = mac.replaceAll(':', '').toUpperCase();
    if (clean.length == 12) {
      return '${clean.substring(0, 2)}:${clean.substring(2, 4)}:'
          '${clean.substring(4, 6)}:${clean.substring(6, 8)}:'
          '${clean.substring(8, 10)}:${clean.substring(10, 12)}';
    }
    return mac;
  }

  /// Assign [mac] to [rowIndex], removing it from any other row first.
  void _assignMac(String mac, int rowIndex) {
    setState(() {
      for (int i = 0; i < _rows.length; i++) {
        if (i != rowIndex && _rows[i].macAddress == mac) {
          _rows[i].macAddress = null;
        }
      }
      _rows[rowIndex].macAddress = mac;
      if (!_scannedMacs.contains(mac)) _scannedMacs.add(mac);
    });
  }

  /// Opens the inline MAC scanner bottom sheet.
  Future<void> _showMacScannerSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MacScannerSheet(rows: _rows),
    );
    if (result != null) {
      final String mac = result['mac'] as String;
      final int rowIndex = result['rowIndex'] as int;
      _assignMac(mac, rowIndex);
    }
  }

  // ── bulk actions ─────────────────────────────────────────────────────────

  Future<void> _bulkSetModel() async {
    String selectedModel = DeviceTemplates.supportedModels.first;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSS) => AlertDialog(
          title: const Text('Set Model for Selected'),
          content: DropdownButtonFormField<String>(
            value: selectedModel,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
            items: DeviceTemplates.supportedModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setSS(() => selectedModel = v!),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selectedModel),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        for (final row in _rows) {
          if (row.selected) row.model = result;
        }
      });
    }
  }

  Future<void> _bulkSetWallpaper() async {
    String? selectedWallpaper;
    final result = await showDialog<_WallpaperChoice>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSS) => AlertDialog(
          title: const Text('Set Wallpaper for Selected'),
          content: DropdownButtonFormField<String?>(
            value: selectedWallpaper,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Wallpaper', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Global Default')),
              ..._wallpapers.map((w) => DropdownMenuItem<String?>(
                    value: 'LOCAL:${w.filename}',
                    child: Text(w.name),
                  )),
            ],
            onChanged: (v) => setSS(() => selectedWallpaper = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () =>
                    Navigator.pop(ctx, _WallpaperChoice(selectedWallpaper)),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        for (final row in _rows) {
          if (row.selected) row.wallpaper = result.value;
        }
      });
    }
  }

  /// Opens the settings editor pre-loaded with the first selected row's
  /// settings and applies the result to ALL selected rows.
  Future<void> _bulkSetSettings() async {
    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) return;
    final first = selected.first;

    final result = await Navigator.push<DeviceSettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceSettingsEditorScreen(
          extension: '(multiple)',
          label: '${selected.length} extensions',
          model: first.model,
          initialSettings: first.deviceSettings,
          initialWallpaper: first.wallpaper,
          wallpapers: _wallpapers,
          otherExtensions: [],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        for (final row in _rows) {
          if (!row.selected) continue;
          row.deviceSettings =
              result.settings.hasOverrides ? result.settings : null;
          if (result.wallpaper != null) row.wallpaper = result.wallpaper;
        }
      });
      await _loadWallpapers();
    }
  }

  // ── per-row settings editor ───────────────────────────────────────────────

  Future<void> _openSettings(int rowIndex) async {
    final row = _rows[rowIndex];
    final others = <ExtensionCloneInfo>[
      for (int i = 0; i < _rows.length; i++)
        if (i != rowIndex)
          (
            extension: _rows[i].device.extension,
            label: _rows[i].device.label,
            settings: _rows[i].deviceSettings,
            wallpaper: _rows[i].wallpaper,
          ),
    ];

    final result = await Navigator.push<DeviceSettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceSettingsEditorScreen(
          extension: row.device.extension,
          label: row.device.label,
          model: row.model,
          initialSettings: row.deviceSettings,
          initialWallpaper: row.wallpaper,
          wallpapers: _wallpapers,
          otherExtensions: others,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        row.deviceSettings =
            result.settings.hasOverrides ? result.settings : null;
        if (result.wallpaper != null) row.wallpaper = result.wallpaper;
      });
      await _loadWallpapers();
    }
  }

  // ── wallpaper upload from row ─────────────────────────────────────────────

  Future<void> _uploadWallpaperForRow(int rowIndex) async {
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
                '${DeviceTemplates.getSpecForModel(selectedModel).height}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.blue),
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
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadWallpapers();
                    setState(() => _rows[rowIndex].wallpaper =
                        'LOCAL:$filename');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Wallpaper uploaded!')));
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Upload failed: $e')));
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
                child: const Text('Cancel')),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }

  // ── confirm import ────────────────────────────────────────────────────────

  Future<void> _confirmImport() async {
    // Determine most-commonly used model to remember.
    final modelCounts = <String, int>{};
    for (final r in _rows) {
      modelCounts[r.model] = (modelCounts[r.model] ?? 0) + 1;
    }
    final mostCommonModel = modelCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    final devices = _rows
        .map((r) => Device(
              model: r.model,
              extension: r.device.extension,
              secret: r.device.secret,
              label: r.device.label,
              macAddress: r.macAddress,
              status: r.macAddress != null ? 'READY' : 'PENDING',
              wallpaper: r.wallpaper,
              deviceSettings: r.deviceSettings,
            ))
        .toList();

    try {
      await DatabaseHelper.instance.insertDevices(devices);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_used_model', mostCommonModel);
      if (mounted) Navigator.pop(context, devices.length);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Import failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedCount = _rows.where((r) => r.selected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Import'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan MAC',
            onPressed: _showMacScannerSheet,
          ),
          Checkbox(
            value: _allSelected ? true : (_anySelected ? null : false),
            tristate: true,
            onChanged: _toggleAll,
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Center(child: Text('All')),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header row (labels the 3 dropdowns)
          Container(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            padding: const EdgeInsets.only(
                left: 48, right: 8, top: 4, bottom: 4),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Model',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11))),
                Expanded(
                    flex: 3,
                    child: Text('Wallpaper',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11))),
                Expanded(
                    flex: 3,
                    child: Text('MAC',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _rows[index];
                return _DeviceRow(
                  row: row,
                  wallpapers: _wallpapers,
                  scannedMacs: _scannedMacs,
                  formatMac: _formatMac,
                  onChanged: () => setState(() {}),
                  onMacChanged: (mac) {
                    setState(() {
                      // Swap: remove from previous owner
                      if (mac != null) {
                        for (int i = 0; i < _rows.length; i++) {
                          if (i != index &&
                              _rows[i].macAddress == mac) {
                            _rows[i].macAddress = null;
                          }
                        }
                      }
                      row.macAddress = mac;
                    });
                  },
                  onTapSettings: () => _openSettings(index),
                  onUploadWallpaper: () =>
                      _uploadWallpaperForRow(index),
                );
              },
            ),
          ),

          // Bulk action bar
          if (_anySelected)
            Container(
              color:
                  Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('$selectedCount selected',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.phone_android,
                        size: 14),
                    label: const Text('Model',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _bulkSetModel,
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wallpaper, size: 14),
                    label: const Text('Wallpaper',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _bulkSetWallpaper,
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.settings, size: 14),
                    label: const Text('Settings',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _bulkSetSettings,
                  ),
                ],
              ),
            ),

          // Bottom confirm/cancel bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text(
                          'Confirm Import (${_rows.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                      ),
                      onPressed: _confirmImport,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _RowState ─────────────────────────────────────────────────────────────

/// Mutable state for a single device row during the review phase.
class _RowState {
  final Device device;
  bool selected;
  String model;
  String? wallpaper;
  String? macAddress;
  DeviceSettings? deviceSettings;

  _RowState({required this.device, String? defaultModel})
      : selected = false,
        model = DeviceTemplates.supportedModels.contains(device.model)
            ? device.model
            : (defaultModel != null &&
                    DeviceTemplates.supportedModels.contains(defaultModel)
                ? defaultModel
                : DeviceTemplates.supportedModels.first),
        wallpaper = device.wallpaper,
        macAddress = device.macAddress,
        deviceSettings = device.deviceSettings;
}

/// Thin wrapper so dialogs can return null as a deliberate "Global Default".
class _WallpaperChoice {
  final String? value;
  const _WallpaperChoice(this.value);
}

// ─── _DeviceRow ────────────────────────────────────────────────────────────

/// A single row in the review list (2-line layout).
class _DeviceRow extends StatelessWidget {
  final _RowState row;
  final List<WallpaperInfo> wallpapers;
  final List<String> scannedMacs;
  final String Function(String) formatMac;
  final VoidCallback onChanged;
  final void Function(String?) onMacChanged;
  final VoidCallback onTapSettings;
  final VoidCallback onUploadWallpaper;

  const _DeviceRow({
    required this.row,
    required this.wallpapers,
    required this.scannedMacs,
    required this.formatMac,
    required this.onChanged,
    required this.onMacChanged,
    required this.onTapSettings,
    required this.onUploadWallpaper,
  });

  @override
  Widget build(BuildContext context) {
    final hasSettings =
        row.deviceSettings != null && row.deviceSettings!.hasOverrides;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Line 1: checkbox + extension info (tappable) ───────────
          Row(
            children: [
              Checkbox(
                value: row.selected,
                onChanged: (v) {
                  row.selected = v ?? false;
                  onChanged();
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onTapSettings,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  row.device.extension,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 13),
                                ),
                                if (hasSettings)
                                  const Padding(
                                    padding: EdgeInsets.only(
                                        left: 3),
                                    child: Text('⚙️',
                                        style: TextStyle(
                                            fontSize: 11)),
                                  ),
                                if (row.macAddress != null)
                                  const Padding(
                                    padding: EdgeInsets.only(
                                        left: 3),
                                    child: Text('📷',
                                        style: TextStyle(
                                            fontSize: 11)),
                                  ),
                              ],
                            ),
                            Text(
                              row.device.label,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey),
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                            if (row.macAddress != null)
                              Text(
                                formatMac(row.macAddress!),
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight:
                                        FontWeight.w500),
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 14, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // ── Line 2: three dropdowns aligned under content ──────────
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                // Model
                Expanded(
                  flex: 3,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: row.model,
                      isExpanded: true,
                      isDense: true,
                      items: DeviceTemplates.supportedModels
                          .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m,
                                  style: const TextStyle(
                                      fontSize: 11))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          row.model = v;
                          onChanged();
                        }
                      },
                    ),
                  ),
                ),
                // Wallpaper + upload button
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: row.wallpaper,
                            isExpanded: true,
                            isDense: true,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Default',
                                    style: TextStyle(
                                        fontSize: 11)),
                              ),
                              ...wallpapers.map((w) =>
                                  DropdownMenuItem<String?>(
                                    value:
                                        'LOCAL:${w.filename}',
                                    child: Text(w.name,
                                        style: const TextStyle(
                                            fontSize: 11),
                                        overflow: TextOverflow
                                            .ellipsis),
                                  )),
                            ],
                            onChanged: (v) {
                              row.wallpaper = v;
                              onChanged();
                            },
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: onUploadWallpaper,
                        child: const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 2),
                          child:
                              Icon(Icons.upload, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                // MAC
                Expanded(
                  flex: 3,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: row.macAddress,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No MAC',
                              style: TextStyle(fontSize: 11)),
                        ),
                        ...scannedMacs.map((mac) =>
                            DropdownMenuItem<String?>(
                              value: mac,
                              child: Text(
                                formatMac(mac),
                                style: const TextStyle(
                                    fontSize: 11),
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: onMacChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _MacScannerSheet ──────────────────────────────────────────────────────

/// Bottom-sheet widget for scanning or manually entering a MAC address and
/// assigning it to a chosen extension.
class _MacScannerSheet extends StatefulWidget {
  final List<_RowState> rows;

  const _MacScannerSheet({required this.rows});

  @override
  State<_MacScannerSheet> createState() => _MacScannerSheetState();
}

class _MacScannerSheetState extends State<_MacScannerSheet> {
  late final MobileScannerController _controller;
  final TextEditingController _macCtrl = TextEditingController();
  int _selectedRowIndex = 0;
  bool _cameraStopped = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.ean13,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
      ],
    );
    // Pre-select the first checked row, or row 0.
    final idx = widget.rows.indexWhere((r) => r.selected);
    _selectedRowIndex = idx >= 0 ? idx : 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    _macCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_cameraStopped) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final clean = raw.replaceAll(':', '').toUpperCase();
    if (clean.length < 12) return;
    setState(() {
      _cameraStopped = true;
      _macCtrl.text = clean;
    });
    _controller.stop();
  }

  void _assign() {
    final raw = _macCtrl.text.trim();
    final clean =
        raw.replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();
    if (clean.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'MAC too short — enter at least 12 hex chars')),
      );
      return;
    }
    Navigator.pop(
        context, {'mac': clean, 'rowIndex': _selectedRowIndex});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Scan MAC Address',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          // Camera or confirmation tick
          SizedBox(
            height: 180,
            child: _cameraStopped
                ? const Center(
                    child: Icon(Icons.check_circle,
                        color: Colors.green, size: 64))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                  ),
          ),
          if (_cameraStopped)
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Rescan'),
              onPressed: () {
                setState(() {
                  _cameraStopped = false;
                  _macCtrl.clear();
                });
                _controller.start();
              },
            ),
          // Manual MAC entry
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _macCtrl,
              decoration: const InputDecoration(
                labelText: 'MAC Address',
                hintText: 'AABBCCDDEEFF',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ),
          // Extension selector
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DropdownButtonFormField<int>(
              value: _selectedRowIndex,
              decoration: const InputDecoration(
                labelText: 'Assign to Extension',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: List.generate(widget.rows.length, (i) {
                final r = widget.rows[i];
                return DropdownMenuItem(
                  value: i,
                  child: Text(
                      '${r.device.extension}  —  ${r.device.label}',
                      overflow: TextOverflow.ellipsis),
                );
              }),
              onChanged: (v) =>
                  setState(() => _selectedRowIndex = v ?? 0),
            ),
          ),
          // Assign button
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Assign MAC'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: _assign,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
