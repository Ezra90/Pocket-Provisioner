import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/button_key.dart';
import '../models/device.dart';
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

  @override
  void dispose() {
    _modelController.dispose();
    _jsonController.dispose();
    super.dispose();
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
        ..fullValue = dev.extension
        ..value = dev.extension
        ..shortDialMode = 'full'
        ..label = dev.label.isNotEmpty ? dev.label : dev.extension;
    }

    _updateJsonField();
    setState(() {});
    _saveLayout();
  }

  /// Opens the key editor dialog.
  /// Loads CSV devices first so the picker is immediately available.
  Future<void> _editKey(ButtonKey key) async {
    final List<Device> csvDevices = await DatabaseHelper.instance.getAllDevices();
    csvDevices.sort((a, b) {
      final aNum = int.tryParse(a.extension) ?? 0;
      final bNum = int.tryParse(b.extension) ?? 0;
      return aNum.compareTo(bNum);
    });

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => KeyEditDialog(
        key_: key,
        csvDevices: csvDevices,
        onSave: (updatedKey) {
          _updateJsonField();
          setState(() {});
        },
      ),
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
      body: SafeArea(
        top: false,
        child: Padding(
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
                    onTap: () async => _editKey(key),
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
                              if (key.label.isNotEmpty) Text(key.label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Key Edit Dialog — CSV picker + manual entry + short dial
// ---------------------------------------------------------------------------

class KeyEditDialog extends StatefulWidget {
  final ButtonKey key_;
  final List<Device> csvDevices;
  final void Function(ButtonKey) onSave;

  const KeyEditDialog({
    required this.key_,
    required this.csvDevices,
    required this.onSave,
  });

  @override
  State<KeyEditDialog> createState() => KeyEditDialogState();
}

class KeyEditDialogState extends State<KeyEditDialog> {
  late String _selectedType;
  late TextEditingController _fullValueController;
  late TextEditingController _labelController;
  late TextEditingController _searchController;
  late TextEditingController _customDigitsController;
  late String _shortDialMode;
  late int _customDigits;

  /// All known extensions — widget.csvDevices merged with every device in the
  /// database.  Loaded asynchronously in initState; falls back to csvDevices
  /// until ready.
  List<Device> _allKnownDevices = [];
  List<Device> _filteredDevices = [];
  bool _showCsvPicker = false;

  /// True once the user has manually typed in the label field.
  /// While false, tapping an extension in the list will also auto-fill the
  /// label; once true it will only fill the extension, preserving the
  /// custom label the user entered.
  bool _labelCustomised = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.key_.type;
    final initialFull = widget.key_.fullValue.isNotEmpty
        ? widget.key_.fullValue
        : widget.key_.value;
    _fullValueController = TextEditingController(text: initialFull);
    _labelController = TextEditingController(text: widget.key_.label);
    _searchController = TextEditingController();
    _shortDialMode = widget.key_.shortDialMode;
    _customDigits = widget.key_.customDigits;
    _customDigitsController =
        TextEditingController(text: _customDigits.toString());

    // Mark as customised when re-opening a button that already has a label.
    // This preserves whatever label the button had (whether it was previously
    // picked from a list or manually typed) and prevents the first extension
    // pick from silently overwriting it.  The user can always tap the
    // "restore known name" icon to reset to the DB default.
    _labelCustomised = widget.key_.label.isNotEmpty;

    _allKnownDevices = List.of(widget.csvDevices);
    _filteredDevices = _allKnownDevices;
    _searchController.addListener(_filterDevices);

    // Load ALL devices from the database and merge (dedup by extension).
    _loadAllDevices();
  }

  Future<void> _loadAllDevices() async {
    final dbDevices = await DatabaseHelper.instance.getAllDevices();
    // Merge: start with csvDevices (current batch takes precedence for labels),
    // then add any DB devices whose extension isn't already present.
    final knownExts = {for (final d in widget.csvDevices) d.extension};
    final merged = List.of(widget.csvDevices);
    for (final d in dbDevices) {
      if (!knownExts.contains(d.extension)) merged.add(d);
    }
    merged.sort((a, b) {
      final aNum = int.tryParse(a.extension) ?? 0;
      final bNum = int.tryParse(b.extension) ?? 0;
      return aNum.compareTo(bNum);
    });
    if (mounted) {
      setState(() {
        _allKnownDevices = merged;
        _filteredDevices = merged;
      });
      _filterDevices(); // re-apply any active search
    }
  }

  @override
  void dispose() {
    _fullValueController.dispose();
    _labelController.dispose();
    _searchController.dispose();
    _customDigitsController.dispose();
    super.dispose();
  }

  void _filterDevices() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filteredDevices = q.isEmpty
          ? _allKnownDevices
          : _allKnownDevices
              .where((d) =>
                  d.extension.contains(q) ||
                  d.label.toLowerCase().contains(q))
              .toList();
    });
  }

  /// Computes the effective (shortened) dial value from [full] and [mode].
  String _computeShortDial(String full, String mode, int customDigits) {
    if (full.isEmpty) return '';
    final int digits = switch (mode) {
      '3digit' => 3,
      '4digit' => 4,
      '5digit' => 5,
      'custom' => customDigits,
      _ => 0,
    };
    if (digits == 0) return full;
    return full.length > digits ? full.substring(full.length - digits) : full;
  }

  String get _effectiveValue => _computeShortDial(
        _fullValueController.text,
        _shortDialMode,
        _customDigits,
      );

  bool get _hasCsvDevices => _allKnownDevices.isNotEmpty;
  bool get _showPicker =>
      _showCsvPicker && (_selectedType == 'blf' || _selectedType == 'speeddial');

  /// Returns the default label for the currently entered extension (from the
  /// known-devices list), or null if not found.
  String? get _knownLabel {
    final ext = _fullValueController.text.trim();
    if (ext.isEmpty) return null;
    try {
      return _allKnownDevices
          .firstWhere((d) => d.extension == ext)
          .label;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final knownLabel = _knownLabel;

    return AlertDialog(
      title: Text("Edit Key ${widget.key_.id}"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Type selector ──────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _selectedType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Type"),
              items: const [
                DropdownMenuItem(value: 'none', child: Text("None")),
                DropdownMenuItem(value: 'blf', child: Text("BLF (Monitor Extension)")),
                DropdownMenuItem(value: 'speeddial', child: Text("Speed Dial")),
                DropdownMenuItem(value: 'line', child: Text("Line (Additional Account)")),
              ],
              onChanged: (v) => setState(() {
                _selectedType = v ?? 'none';
                if (_selectedType == 'none') _showCsvPicker = false;
              }),
            ),

            if (_selectedType != 'none') ...[
              const SizedBox(height: 12),

              // ── Extension picker toggle (BLF / Speed Dial only) ───────────
              if (_hasCsvDevices &&
                  (_selectedType == 'blf' || _selectedType == 'speeddial'))
                OutlinedButton.icon(
                  icon: Icon(_showCsvPicker
                      ? Icons.keyboard_hide
                      : Icons.list_alt),
                  label: Text(_showCsvPicker
                      ? "Hide list — type manually below"
                      : "Pick from known extensions (${_allKnownDevices.length})"),
                  onPressed: () =>
                      setState(() => _showCsvPicker = !_showCsvPicker),
                ),

              // ── Searchable extension list ──────────────────────────────────
              if (_showPicker) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: "Search by extension or name…",
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 160,
                  child: _filteredDevices.isEmpty
                      ? const Center(child: Text("No matches"))
                      : ListView.builder(
                          itemCount: _filteredDevices.length,
                          itemBuilder: (ctx, i) {
                            final dev = _filteredDevices[i];
                            final isSelected =
                                _fullValueController.text.trim() == dev.extension;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              leading: CircleAvatar(
                                radius: 14,
                                child: Text(dev.extension,
                                    style: const TextStyle(fontSize: 10)),
                              ),
                              title: Text(dev.extension,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: Text(dev.label,
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () {
                                setState(() {
                                  // Always fill the extension number.
                                  _fullValueController.text = dev.extension;
                                  // Only auto-fill the label when the user
                                  // hasn't explicitly customised it yet.
                                  if (!_labelCustomised) {
                                    _labelController.text = dev.label;
                                  }
                                  _showCsvPicker = false;
                                });
                              },
                            );
                          },
                        ),
                ),
                const Divider(),
              ],

              // ── Extension number (manual / result of pick) ─────────────────
              TextField(
                controller: _fullValueController,
                decoration: InputDecoration(
                  labelText: "Extension / Number",
                  hintText: "e.g. 101",
                  helperText: _shortDialMode != 'full'
                      ? "Short dial: $_effectiveValue"
                      : null,
                  helperStyle: const TextStyle(color: Colors.blue),
                ),
                onChanged: (_) => setState(() {}), // refresh preview + known label
              ),
              const SizedBox(height: 8),

              // ── Button label ───────────────────────────────────────────────
              // The label is always fully editable.  If the extension matches a
              // known device the known name is shown as helper text so the user
              // can decide whether to keep it, override it, or restore it.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      decoration: InputDecoration(
                        labelText: "Button Label",
                        hintText: knownLabel ?? "e.g. Reception",
                        helperText: _labelCustomised && knownLabel != null
                            ? "Known name: $knownLabel"
                            : "Leave blank to use the extension name",
                        helperStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      // Mark as customised as soon as the user types.
                      onChanged: (_) =>
                          setState(() => _labelCustomised = true),
                    ),
                  ),
                  // "Restore known name" button — only shown when the current
                  // extension matches a known device.
                  if (knownLabel != null)
                    Tooltip(
                      message: 'Restore known name: "$knownLabel"',
                      child: IconButton(
                        icon: const Icon(Icons.person_pin,
                            size: 20, color: Colors.blueGrey),
                        onPressed: () => setState(() {
                          _labelController.text = knownLabel;
                          _labelCustomised = false;
                        }),
                      ),
                    ),
                ],
              ),

              // ── Short Dial ─────────────────────────────────────────────────
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _shortDialMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Short Dial Mode",
                  helperText:
                      "Shorten the dialled number in the generated config",
                ),
                items: const [
                  DropdownMenuItem(value: 'full', child: Text("Full — use complete number")),
                  DropdownMenuItem(value: '3digit', child: Text("3-digit — last 3 digits")),
                  DropdownMenuItem(value: '4digit', child: Text("4-digit — last 4 digits")),
                  DropdownMenuItem(value: '5digit', child: Text("5-digit — last 5 digits")),
                  DropdownMenuItem(value: 'custom', child: Text("Custom — specify digits")),
                ],
                onChanged: (v) =>
                    setState(() => _shortDialMode = v ?? 'full'),
              ),
              if (_shortDialMode == 'custom') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customDigitsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: "Number of trailing digits to keep"),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) setState(() => _customDigits = n);
                  },
                ),
              ],

              // ── Preview ────────────────────────────────────────────────────
              if (_fullValueController.text.isNotEmpty &&
                  _shortDialMode != 'full') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.preview, size: 16,
                          color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Full: ${_fullValueController.text}   →   Dialled: $_effectiveValue",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            final full = _fullValueController.text.trim();
            // If label is blank, resolve from known devices.
            final rawLabel = _labelController.text.trim();
            final resolvedLabel = rawLabel.isNotEmpty
                ? rawLabel
                : (_knownLabel ?? '');
            widget.key_
              ..type = _selectedType
              ..fullValue = full
              ..shortDialMode = _shortDialMode
              ..customDigits = _customDigits
              ..label = resolvedLabel;
            widget.key_.applyShortDial();
            if (full.isEmpty) widget.key_.value = '';
            widget.onSave(widget.key_);
            Navigator.pop(context);
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
