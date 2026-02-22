import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';
import '../models/device_settings.dart';
import '../services/wallpaper_service.dart';
import 'device_settings_editor_screen.dart';

/// Central screen for managing all extensions/handsets.
/// Lists ALL devices (PENDING, READY, PROVISIONED) and allows:
///   - Tap to open per-device settings editor
///   - FAB (+) to add a single extension manually
///   - Swipe-to-delete
///   - Inline MAC scan/entry
///   - Pull-to-refresh
class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  List<Device> _devices = [];
  List<WallpaperInfo> _wallpapers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final devices = await DatabaseHelper.instance.getAllDevices();
    final wallpapers = await WallpaperService.listWallpapers();
    if (mounted) {
      setState(() {
        _devices = devices;
        _wallpapers = wallpapers;
        _loading = false;
      });
    }
  }

  // ── status badge helper ──────────────────────────────────────────────────

  Widget _statusBadge(String status) {
    final (color, label) = switch (status.toUpperCase()) {
      'READY' => (Colors.green, 'READY'),
      'PROVISIONED' => (Colors.blue, 'DONE'),
      _ => (Colors.orange, 'PENDING'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── open per-device settings editor ──────────────────────────────────────

  Future<void> _openSettings(Device device) async {
    final others = _devices
        .where((d) => d.id != device.id)
        .map((d) => (
              extension: d.extension,
              label: d.label,
              settings: d.deviceSettings,
              wallpaper: d.wallpaper,
            ) as ExtensionCloneInfo)
        .toList();

    final result = await Navigator.push<DeviceSettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceSettingsEditorScreen(
          extension: device.extension,
          label: device.label,
          model: device.model,
          initialSettings: device.deviceSettings,
          initialWallpaper: device.wallpaper,
          wallpapers: _wallpapers,
          otherExtensions: others,
        ),
      ),
    );

    if (result != null && device.id != null) {
      final newSettings =
          result.settings.hasOverrides ? result.settings : null;
      await DatabaseHelper.instance.updateDeviceSettings(
        device.id!,
        newSettings,
        result.wallpaper,
      );
      await _load();
    }
  }

  // ── MAC assignment ────────────────────────────────────────────────────────

  Future<void> _assignMac(Device device) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MacEntrySheet(
        extension: device.extension,
        label: device.label,
      ),
    );

    if (result != null && result.isNotEmpty && device.id != null) {
      final clean = result.replaceAll(':', '').toUpperCase();
      await DatabaseHelper.instance.updateDeviceMac(device.id!, clean);
      await _load();
    }
  }

  // ── delete extension ──────────────────────────────────────────────────────

  Future<bool> _confirmDelete(Device device) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Extension?'),
            content: Text(
                'Delete Ext ${device.extension} (${device.label})?\n\nThis cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── "Add Extension" FAB ───────────────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final extCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    String selectedModel = DeviceTemplates.supportedModels.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text('Add Extension'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: extCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Extension (required)',
                    hintText: 'e.g. 101',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: secretCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SIP Password (required)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label / Name (optional)',
                    hintText: 'Defaults to extension number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                  items: DeviceTemplates.supportedModels
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setDS(() => selectedModel = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      extCtrl.dispose();
      secretCtrl.dispose();
      labelCtrl.dispose();
      return;
    }

    final ext = extCtrl.text.trim();
    final secret = secretCtrl.text.trim();
    final label = labelCtrl.text.trim();
    extCtrl.dispose();
    secretCtrl.dispose();
    labelCtrl.dispose();

    if (ext.isEmpty || secret.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Extension and password are required')),
        );
      }
      return;
    }

    await DatabaseHelper.instance.insertDevice(Device(
      model: selectedModel,
      extension: ext,
      secret: secret,
      label: label.isEmpty ? ext : label,
      status: 'PENDING',
    ));
    await _load();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _devices.isEmpty
                    ? ListView(
                        children: const [
                          Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No extensions yet.\nTap + to add one, or import a CSV from the dashboard.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return Dismissible(
                            key: ValueKey(device.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding:
                                  const EdgeInsets.only(right: 16),
                              color: Colors.red,
                              child: const Icon(Icons.delete,
                                  color: Colors.white),
                            ),
                            confirmDismiss: (_) =>
                                _confirmDelete(device),
                            onDismissed: (_) async {
                              if (device.id != null) {
                                await DatabaseHelper.instance
                                    .deleteDevice(device.id!);
                              }
                              await _load();
                            },
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                child: FittedBox(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(4),
                                    child: Text(
                                      device.extension,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(device.label),
                              subtitle: Text(
                                '${device.model}  •  '
                                '${device.macAddress ?? 'No MAC'}',
                                style: const TextStyle(
                                    fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _statusBadge(device.status),
                                  const SizedBox(width: 4),
                                  // Scan/enter MAC button
                                  IconButton(
                                    icon: const Icon(
                                        Icons.qr_code_scanner,
                                        size: 20),
                                    tooltip: 'Assign MAC',
                                    onPressed: () =>
                                        _assignMac(device),
                                  ),
                                ],
                              ),
                              onTap: () => _openSettings(device),
                            ),
                          );
                        },
                      ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Add Extension',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── MAC entry bottom sheet ────────────────────────────────────────────────────

class _MacEntrySheet extends StatefulWidget {
  final String extension;
  final String label;
  const _MacEntrySheet({required this.extension, required this.label});

  @override
  State<_MacEntrySheet> createState() => _MacEntrySheetState();
}

class _MacEntrySheetState extends State<_MacEntrySheet> {
  final _manualCtrl = TextEditingController();
  MobileScannerController? _scannerCtrl;
  bool _scanning = false;

  @override
  void dispose() {
    _manualCtrl.dispose();
    _scannerCtrl?.dispose();
    super.dispose();
  }

  void _startScan() {
    _scannerCtrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.ean13,
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
      ],
    );
    setState(() => _scanning = true);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final cleaned =
          raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
      if (cleaned.length >= 12) {
        final mac = cleaned.substring(0, 12);
        Navigator.pop(context, mac);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign MAC — Ext ${widget.extension} (${widget.label})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),

            if (_scanning) ...[
              SizedBox(
                height: 200,
                child: MobileScanner(
                  controller: _scannerCtrl!,
                  onDetect: _onDetect,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    setState(() {
                      _scannerCtrl?.dispose();
                      _scannerCtrl = null;
                      _scanning = false;
                    }),
                child: const Text('Cancel Scan'),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Barcode'),
              ),
              const SizedBox(height: 12),
              const Text('— or enter manually —',
                  style:
                      TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualCtrl,
                      decoration: const InputDecoration(
                        labelText: 'MAC Address',
                        hintText: 'e.g. AABBCCDDEEFF',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final mac = _manualCtrl.text.trim();
                      if (mac.length >= 12) {
                        Navigator.pop(context, mac);
                      }
                    },
                    child: const Text('Assign'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
