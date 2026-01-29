import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/button_key.dart';
import '../services/button_layout_service.dart';
import '../data/database_helper.dart';

class ButtonLayoutEditorScreen extends StatefulWidget {
  const ButtonLayoutEditorScreen({super.key});

  @override
  State<ButtonLayoutEditorScreen> createState() => _ButtonLayoutEditorScreenState();
}

class _ButtonLayoutEditorScreenState extends State<ButtonLayoutEditorScreen> {
  String _currentModel = 'T58A'; // Common default Yealink model
  List<ButtonKey> _layout = List.generate(30, (i) => ButtonKey(i + 1)); // Keys 1-30
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _modelController.text = _currentModel;
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    _layout = await ButtonLayoutService.getLayoutForModel(_currentModel);
    if (_layout.isEmpty) {
      _layout = List.generate(30, (i) => ButtonKey(i + 1));
    }
    _updateJsonField();
    setState(() {});
  }

  Future<void> _saveLayout() async {
    await ButtonLayoutService.saveLayoutForModel(_currentModel, _layout);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Layout saved for this model!")),
      );
    }
  }

  void _updateJsonField() {
    _jsonController.text = json.encode(_layout.map((k) => k.toJson()).toList());
  }

  Future<void> _applyPastedJson() async {
    try {
      final List<dynamic> decoded = json.decode(_jsonController.text);
      final List<ButtonKey> newLayout = decoded.map((e) => ButtonKey.fromJson(e)).toList();
      // Pad to 30 keys if shorter
      while (newLayout.length < 30) {
        newLayout.add(ButtonKey(newLayout.length + 1));
      }
      setState(() {
        _layout = newLayout.take(30).toList();
      });
      _saveLayout(); // Auto-save after apply
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Invalid JSON: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _autoSequentialBlf() async {
    final devices = await DatabaseHelper.instance.getAllDevices();
    if (devices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No devices imported yet — import a CSV first")),
        );
      }
      return;
    }

    // Sort numerically by extension (fallback to 0 if non-numeric)
    devices.sort((a, b) {
      final aNum = int.tryParse(a.extension) ?? 0;
      final bNum = int.tryParse(b.extension) ?? 0;
      return aNum.compareTo(bNum);
    });

    // Fill keys starting from 1 (skip key 1 if it's typically the primary line)
    for (int i = 0; i < _layout.length && i < devices.length; i++) {
      final dev = devices[i];
      _layout[i]
        ..type = 'blf'
        ..value = dev.extension
        ..label = dev.label.isNotEmpty ? dev.label : dev.extension;
    }

    _updateJsonField();
    setState(() {});
    _saveLayout();
  }

  void _editKey(ButtonKey key) {
    showDialog(
      context: context,
      builder: (context) {
        final typeController = TextEditingController(text: key.type);
        final valueController = TextEditingController(text: key.value);
        final labelController = TextEditingController(text: key.label);

        return AlertDialog(
          title: Text("Edit Key ${key.id}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: key.type,
                decoration: const InputDecoration(labelText: "Type"),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text("None")),
                  DropdownMenuItem(value: 'blf', child: Text("BLF (Monitor Extension)")),
                  DropdownMenuItem(value: 'speeddial', child: Text("Speed Dial")),
                  DropdownMenuItem(value: 'line', child: Text("Line (Additional Account)")),
                ],
                onChanged: (v) => key.type = v ?? 'none',
              ),
              const SizedBox(height: 10),
              if (key.type != 'none') ...[
                TextField(
                  controller: valueController,
                  decoration: const InputDecoration(labelText: "Value (Extension / Number)"),
                  onChanged: (v) => key.value = v,
                ),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: "Custom Label (optional — auto-uses device label for BLF)"),
                  onChanged: (v) => key.label = v,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                key
                  ..type = typeController.text
                  ..value = valueController.text
                  ..label = labelController.text;
                _updateJsonField();
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Button Layout Editor"),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: "Copy JSON",
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _jsonController.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Layout JSON copied to clipboard!")),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: "Model Name (e.g. T58A, T46S)",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _currentModel = v.trim().toUpperCase(),
              onSubmitted: (_) => _loadLayout(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton(onPressed: _loadLayout, child: const Text("Load Layout")),
                ElevatedButton(onPressed: _autoSequentialBlf, child: const Text("Auto Sequential BLF")),
                ElevatedButton(onPressed: _saveLayout, child: const Text("Save Layout")),
                ElevatedButton(onPressed: _applyPastedJson, child: const Text("Apply Pasted JSON")),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Tap a key to edit • 30 programmable keys (covers most Yealink models)", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1.0,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _layout.length,
                itemBuilder: (context, index) {
                  final key = _layout[index];
                  return GestureDetector(
                    onTap: () => _editKey(key),
                    child: Card(
                      color: key.type == 'none' ? Colors.grey[300] : Colors.blue[100],
                      elevation: 3,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("${key.id}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Text(key.type.toUpperCase(), style: const TextStyle(fontSize: 12)),
                              if (key.value.isNotEmpty) Text(key.value, style: const TextStyle(fontSize: 11)),
                              if (key.label.isNotEmpty) Text(key.label, style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 30),
            const Text("Copy/Paste Layout JSON (share between models/jobs/devices)", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            TextField(
              controller: _jsonController,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText: "Edit/paste JSON here, then tap 'Apply Pasted JSON'",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
