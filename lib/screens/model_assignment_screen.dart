import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';
import '../services/wallpaper_service.dart';

/// Intermediate review screen shown after CSV parsing.
/// Allows per-device model and wallpaper assignment before committing to the DB.
class ModelAssignmentScreen extends StatefulWidget {
  final List<Device> devices;

  const ModelAssignmentScreen({super.key, required this.devices});

  @override
  State<ModelAssignmentScreen> createState() => _ModelAssignmentScreenState();
}

class _ModelAssignmentScreenState extends State<ModelAssignmentScreen> {
  /// Mutable copy of the parsed device list with per-row model/wallpaper state.
  late List<_RowState> _rows;

  /// Available wallpapers loaded from WallpaperService.
  List<WallpaperInfo> _wallpapers = [];

  /// Whether checkboxes are all selected.
  bool get _allSelected => _rows.isNotEmpty && _rows.every((r) => r.selected);

  /// Whether at least one checkbox is selected.
  bool get _anySelected => _rows.any((r) => r.selected);

  @override
  void initState() {
    super.initState();
    _rows = widget.devices.map((d) => _RowState(device: d)).toList();
    _loadWallpapers();
  }

  Future<void> _loadWallpapers() async {
    final wallpapers = await WallpaperService.listWallpapers();
    if (mounted) {
      setState(() => _wallpapers = wallpapers);
    }
  }

  void _toggleAll(bool? value) {
    final checked = value ?? false;
    setState(() {
      for (final row in _rows) {
        row.selected = checked;
      }
    });
  }

  /// Show a dialog to pick a model and apply it to all selected rows.
  Future<void> _bulkSetModel() async {
    String selectedModel = DeviceTemplates.supportedModels.first;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set Model for Selected'),
          content: DropdownButtonFormField<String>(
            value: selectedModel,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
            items: DeviceTemplates.supportedModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setDialogState(() => selectedModel = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selectedModel),
              child: const Text('Apply'),
            ),
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

  /// Show a dialog to pick a wallpaper and apply it to all selected rows.
  Future<void> _bulkSetWallpaper() async {
    String? selectedWallpaper; // null = Global Default
    final result = await showDialog<_WallpaperChoice>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set Wallpaper for Selected'),
          content: DropdownButtonFormField<String?>(
            value: selectedWallpaper,
            decoration: const InputDecoration(
              labelText: 'Wallpaper',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Global Default'),
              ),
              ..._wallpapers.map(
                (w) => DropdownMenuItem<String?>(
                  value: 'LOCAL:${w.filename}',
                  child: Text(w.name),
                ),
              ),
            ],
            onChanged: (v) => setDialogState(() => selectedWallpaper = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, _WallpaperChoice(selectedWallpaper)),
              child: const Text('Apply'),
            ),
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

  Future<void> _confirmImport() async {
    final devices = _rows
        .map((r) => Device(
              model: r.model,
              extension: r.device.extension,
              secret: r.device.secret,
              label: r.device.label,
              macAddress: r.device.macAddress,
              status: r.device.status,
              wallpaper: r.wallpaper,
            ))
        .toList();

    try {
      await DatabaseHelper.instance.insertDevices(devices);
      if (mounted) {
        Navigator.pop(context, devices.length);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
          // Header row
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: const Row(
              children: [
                SizedBox(width: 32),
                Expanded(flex: 2, child: Text('Ext / Label', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('Model', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('Wallpaper', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _rows[index];
                return _DeviceRow(
                  row: row,
                  wallpapers: _wallpapers,
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),
          // Bulk action bar (shown when anything is selected)
          if (_anySelected)
            Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '$selectedCount selected',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.phone_android, size: 16),
                    label: const Text('Set Model'),
                    onPressed: _bulkSetModel,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wallpaper, size: 16),
                    label: const Text('Set Wallpaper'),
                    onPressed: _bulkSetWallpaper,
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
                      label: Text('Confirm Import (${_rows.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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

/// Mutable state for a single device row in the review list.
class _RowState {
  final Device device;
  bool selected;
  String model;
  String? wallpaper; // null = Global Default

  _RowState({required this.device})
      : selected = false,
        model = DeviceTemplates.supportedModels.contains(device.model)
            ? device.model
            : DeviceTemplates.supportedModels.first,
        wallpaper = device.wallpaper;
}

/// A thin wrapper so dialogs can return null as a deliberate "Global Default" choice.
class _WallpaperChoice {
  final String? value;
  const _WallpaperChoice(this.value);
}

/// A single row in the review list.
class _DeviceRow extends StatelessWidget {
  final _RowState row;
  final List<WallpaperInfo> wallpapers;
  final VoidCallback onChanged;

  const _DeviceRow({
    required this.row,
    required this.wallpapers,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: row.selected,
            onChanged: (v) {
              row.selected = v ?? false;
              onChanged();
            },
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.device.extension,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  row.device.label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: row.model,
                isExpanded: true,
                isDense: true,
                items: DeviceTemplates.supportedModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
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
          Expanded(
            flex: 3,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: row.wallpaper,
                isExpanded: true,
                isDense: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Global Default', style: TextStyle(fontSize: 12)),
                  ),
                  ...wallpapers.map(
                    (w) => DropdownMenuItem<String?>(
                      value: 'LOCAL:${w.filename}',
                      child: Text(w.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) {
                  row.wallpaper = v;
                  onChanged();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
