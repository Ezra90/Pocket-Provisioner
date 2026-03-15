import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/button_key.dart';
import '../models/device.dart';
import '../services/button_layout_service.dart';
import 'button_layout_editor.dart';
import 'physical_button_editor.dart';

/// Full-screen button layout editor scoped to a single extension.
/// Returns the edited [List<ButtonKey>] via [Navigator.pop].
class PerExtensionButtonEditorScreen extends StatefulWidget {
  final String extension;
  final String label;
  final String model;
  final List<ButtonKey>? initialLayout;

  /// Other extensions in the batch — used for "Auto BLF" and the BLF picker.
  final List<({String extension, String label})> batchExtensions;

  const PerExtensionButtonEditorScreen({
    super.key,
    required this.extension,
    required this.label,
    required this.model,
    this.initialLayout,
    this.batchExtensions = const [],
  });

  @override
  State<PerExtensionButtonEditorScreen> createState() =>
      _PerExtensionButtonEditorScreenState();
}

class _PerExtensionButtonEditorScreenState
    extends State<PerExtensionButtonEditorScreen> {
  List<ButtonKey> _layout = [];
  final TextEditingController _jsonCtrl = TextEditingController();
  final TextEditingController _csvCtrl = TextEditingController();
  bool _loaded = false;

  /// Model-specific max key count resolved once from the physical layout.
  late final int _maxKeys;

  @override
  void initState() {
    super.initState();
    _maxKeys =
        DeviceTemplates.getPhysicalLayout(widget.model).totalKeyCount;
    _initLayout();
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    _csvCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLayout() async {
    List<ButtonKey> layout;
    if (widget.initialLayout != null && widget.initialLayout!.isNotEmpty) {
      layout = widget.initialLayout!.map((k) => k.clone()).toList();
    } else {
      // Try loading the model-level default layout
      final modelLayout =
          await ButtonLayoutService.getLayoutForModel(widget.model);
      layout = modelLayout.isNotEmpty
          ? modelLayout.map((k) => k.clone()).toList()
          : List.generate(_maxKeys, (i) => ButtonKey(i + 1));
    }
    _updateJson(layout);
    if (mounted) {
      setState(() {
        _layout = layout;
        _loaded = true;
      });
    }
  }

  void _updateJson(List<ButtonKey> layout) {
    _jsonCtrl.text = jsonEncode(layout.map((k) => k.toJson()).toList());
  }

  /// Shows a dialog to copy button layout from another extension.
  Future<void> _copyFromOtherExtension() async {
    // Load all devices from database that have button layouts configured
    final allDevices = await DatabaseHelper.instance.getAllDevices();
    final devicesWithLayouts = allDevices.where((d) =>
        d.deviceSettings?.buttonLayout != null &&
        d.deviceSettings!.buttonLayout!.isNotEmpty &&
        d.deviceSettings!.buttonLayout!.any((k) => k.type != 'none') &&
        d.extension != widget.extension).toList();

    if (devicesWithLayouts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other extensions have button layouts configured')),
        );
      }
      return;
    }

    final selected = await showDialog<Device>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy Layout From...'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devicesWithLayouts.length,
            itemBuilder: (_, i) {
              final device = devicesWithLayouts[i];
              final buttonCount = device.deviceSettings?.buttonLayout
                  ?.where((k) => k.type != 'none').length ?? 0;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(device.extension),
                ),
                title: Text('Ext ${device.extension} - ${device.label}'),
                subtitle: Text('${device.model} • $buttonCount buttons configured'),
                onTap: () => Navigator.pop(ctx, device),
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

    if (selected != null && selected.deviceSettings?.buttonLayout != null) {
      setState(() {
        _layout = selected.deviceSettings!.buttonLayout!.map((k) => k.clone()).toList();
        // Ensure layout has correct number of keys
        while (_layout.length < _maxKeys) {
          _layout.add(ButtonKey(_layout.length + 1));
        }
        if (_layout.length > _maxKeys) {
          _layout = _layout.take(_maxKeys).toList();
        }
      });
      _updateJson(_layout);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied layout from Ext ${selected.extension}')),
        );
      }
    }
  }

  /// Shows dialog to import button layout from CSV format.
  /// CSV format: Type,Extension/Value,Label (one per line)
  /// Example:
  /// blf,101,Reception
  /// blf,102,Kitchen
  /// speeddial,*97,Voicemail
  Future<void> _importFromCsv() async {
    _csvCtrl.clear();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import from CSV'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste CSV data with one button per line:\nType,Extension/Value,Label',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                'Supported types: blf, speeddial, line, voicemail, transfer, park, dtmf',
                style: TextStyle(fontSize: 11, color: Colors.blue),
              ),
              const SizedBox(height: 8),
              const Text(
                'Example:\nblf,101,Reception\nblf,102,Kitchen\nspeeddial,*97,Voicemail',
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _csvCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Paste CSV here...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result != true || _csvCtrl.text.isEmpty) return;

    try {
      final lines = _csvCtrl.text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      int imported = 0;
      for (int i = 0; i < lines.length && i < _maxKeys; i++) {
        final parts = lines[i].split(',').map((p) => p.trim()).toList();
        if (parts.isEmpty) continue;
        
        final type = parts[0].toLowerCase();
        final value = parts.length > 1 ? parts[1] : '';
        final label = parts.length > 2 ? parts[2] : value;

        if (['blf', 'speeddial', 'speed_dial', 'line', 'voicemail', 'transfer', 'park', 'dtmf'].contains(type)) {
          _layout[i]
            ..type = type == 'speed_dial' ? 'speeddial' : type
            ..fullValue = value
            ..value = value
            ..label = label
            ..shortDialMode = 'full';
          imported++;
        }
      }
      setState(() {});
      _updateJson(_layout);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $imported buttons from CSV')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Export current layout to CSV format.
  void _exportToCsv() {
    final buf = StringBuffer();
    for (final key in _layout) {
      if (key.type == 'none') continue;
      buf.writeln('${key.type},${key.fullValue},${key.label}');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layout CSV copied to clipboard')),
    );
  }

  /// Edit display names for all configured buttons.
  Future<void> _editDisplayNames() async {
    final configuredButtons = _layout.where((k) => k.type != 'none').toList();
    if (configuredButtons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No buttons configured to edit')),
      );
      return;
    }

    // Create controllers for each button's label
    final controllers = <int, TextEditingController>{};
    for (final button in configuredButtons) {
      controllers[button.id] = TextEditingController(text: button.label);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Button Labels'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: configuredButtons.length,
            itemBuilder: (_, i) {
              final button = configuredButtons[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: controllers[button.id],
                  decoration: InputDecoration(
                    labelText: 'Key ${button.id}: ${button.type} → ${button.fullValue}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        for (final button in configuredButtons) {
          button.label = controllers[button.id]?.text ?? button.label;
        }
      });
      _updateJson(_layout);
    }

    // Dispose controllers
    for (final ctrl in controllers.values) {
      ctrl.dispose();
    }
  }

  void _autoSequentialBlf() {
    if (widget.batchExtensions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No other extensions in this import batch')),
      );
      return;
    }

    final sorted = List.of(widget.batchExtensions)
      ..sort((a, b) {
        final aNum = int.tryParse(a.extension) ?? 0;
        final bNum = int.tryParse(b.extension) ?? 0;
        return aNum.compareTo(bNum);
      });

    setState(() {
      for (int i = 0; i < _layout.length && i < sorted.length; i++) {
        final ext = sorted[i];
        _layout[i]
          ..type = 'blf'
          ..fullValue = ext.extension
          ..value = ext.extension
          ..shortDialMode = 'full'
          ..label = ext.label.isNotEmpty ? ext.label : ext.extension;
      }
    });
    _updateJson(_layout);
  }

  Future<void> _applyJson() async {
    try {
      final decoded = jsonDecode(_jsonCtrl.text) as List<dynamic>;
      final parsed = decoded
          .map((e) => ButtonKey.fromJson(e as Map<String, dynamic>))
          .toList();
      while (parsed.length < _maxKeys) {
        parsed.add(ButtonKey(parsed.length + 1));
      }
      setState(() => _layout = parsed.take(_maxKeys).toList());
      _updateJson(_layout);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Invalid JSON: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearAll() {
    setState(() => _layout = List.generate(_maxKeys, (i) => ButtonKey(i + 1)));
    _updateJson(_layout);
  }

  Future<void> _editKey(ButtonKey key) async {
    // Wrap batch extensions as Device objects (KeyEditDialog expects List<Device>)
    final devices = widget.batchExtensions
        .map((e) => Device(
              model: '',
              extension: e.extension,
              secret: '',
              label: e.label,
            ))
        .toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.extension) ?? 0;
        final bNum = int.tryParse(b.extension) ?? 0;
        return aNum.compareTo(bNum);
      });

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => KeyEditDialog(
        key_: key,
        csvDevices: devices,
        onSave: (_) {
          _updateJson(_layout);
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Button Layout')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final programmedCount =
        _layout.where((k) => k.type != 'none').length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Button Layout',
                style: TextStyle(fontSize: 16)),
            Text(
              'Ext ${widget.extension}  —  ${widget.label}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          // Open physical / visual layout editor
          IconButton(
            icon: const Icon(Icons.phone_android),
            tooltip: 'Visual handset layout',
            onPressed: () async {
              final result =
                  await Navigator.push<List<ButtonKey>>(
                context,
                MaterialPageRoute(
                  builder: (_) => PhysicalButtonEditorScreen(
                    extension: widget.extension,
                    label: widget.label,
                    model: widget.model,
                    initialLayout: _layout,
                    batchExtensions: widget.batchExtensions,
                  ),
                ),
              );
              if (result != null) {
                setState(() => _layout = result);
                _updateJson(result);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy JSON',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _jsonCtrl.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Layout JSON copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save layout',
            onPressed: () => Navigator.pop(context, _layout),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Action bar - row 1: Primary actions
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text('Auto BLF from Batch',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _autoSequentialBlf,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy, size: 15),
                  label: const Text('Copy From...',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _copyFromOtherExtension,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 15),
                  label: const Text('Edit Labels',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _editDisplayNames,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Action bar - row 2: Import/Export
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 15),
                  label: const Text('Import CSV',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _importFromCsv,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 15),
                  label: const Text('Export CSV',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _exportToCsv,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.clear_all, size: 15),
                  label: const Text('Clear All',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _clearAll,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.code, size: 15),
                  label: const Text('Apply JSON',
                      style: TextStyle(fontSize: 12)),
                  onPressed: _applyJson,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$programmedCount / ${_layout.length} buttons programmed  •  Tap a button to edit',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            // Button grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                childAspectRatio: 1.0,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: _layout.length,
              itemBuilder: (_, i) {
                final key = _layout[i];
                return GestureDetector(
                  onTap: () => _editKey(key),
                  child: Card(
                    color: key.type == 'none'
                        ? Colors.grey.shade300
                        : Colors.blue.shade100,
                    elevation: 2,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Text('${key.id}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            Text(key.type.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 10)),
                            if (key.value.isNotEmpty)
                              Text(key.value,
                                  style: const TextStyle(
                                      fontSize: 10),
                                  overflow:
                                      TextOverflow.ellipsis),
                            if (key.label.isNotEmpty)
                              Text(key.label,
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.black54),
                                  overflow:
                                      TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 12),
            // JSON field
            TextField(
              controller: _jsonCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                helperText:
                    'Edit/paste JSON here, then tap Apply JSON',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
