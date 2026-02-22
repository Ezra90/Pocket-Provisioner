import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action bar
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
            Expanded(
              child: GridView.builder(
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
      ),
    );
  }
}
