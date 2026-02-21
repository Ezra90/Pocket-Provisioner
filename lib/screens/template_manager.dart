import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/mustache_template_service.dart';

class TemplateManagerScreen extends StatefulWidget {
  const TemplateManagerScreen({super.key});

  @override
  State<TemplateManagerScreen> createState() => _TemplateManagerScreenState();
}

class _TemplateManagerScreenState extends State<TemplateManagerScreen> {
  final _keyController = TextEditingController();
  final _contentController = TextEditingController();

  // Incremented to force FutureBuilder to re-fetch after mutations
  int _listVersion = 0;

  @override
  void dispose() {
    _keyController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // --- IMPORT: pick a .mustache / .cfg / .xml file and load its text ---
  Future<void> _importFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final File file = File(result.files.single.path!);
    final String content = await file.readAsString();
    final String filename = result.files.single.name;

    setState(() {
      _contentController.text = content;
      if (_keyController.text.isEmpty) {
        // Use first dot-segment as template key suggestion
        _keyController.text = filename.split('.').first;
      }
    });

    _showSnack('Imported $filename — edit the key then press Save');
  }

  // --- EXPORT: delegate to service which shares via share_plus ---
  Future<void> _exportTemplate() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnack('Enter a Template Key to export');
      return;
    }
    try {
      await MustacheTemplateService.instance.exportTemplate(key);
    } catch (e) {
      _showSnack('Export failed: $e');
    }
  }

  // --- SAVE: write content as a custom template file ---
  Future<void> _save() async {
    final key = _keyController.text.trim();
    final content = _contentController.text;
    if (key.isEmpty || content.isEmpty) {
      _showSnack('Template key and content are both required');
      return;
    }
    await MustacheTemplateService.instance.saveCustomTemplate(key, content);
    setState(() => _listVersion++);
    if (mounted) {
      _showSnack('Saved "$key"');
      Navigator.pop(context);
    }
  }

  // --- LOAD BUNDLED TEMPLATE into the editor ---
  Future<void> _loadTemplate(String key) async {
    try {
      final content = await MustacheTemplateService.instance.loadTemplate(key);
      setState(() {
        _keyController.text = key;
        _contentController.text = content;
      });
    } catch (e) {
      _showSnack('Could not load template: $e');
    }
  }

  // --- DELETE a custom override (restores bundled default) ---
  Future<void> _deleteCustom(String key) async {
    await MustacheTemplateService.instance.deleteCustomTemplate(key);
    setState(() => _listVersion++);
    _showSnack('Custom override for "$key" deleted — bundled default restored');
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Template Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import .mustache file',
            onPressed: _importFile,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export / Share',
            onPressed: _exportTemplate,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // --- TEMPLATE LIST ---
            FutureBuilder<List<TemplateInfo>>(
              key: ValueKey(_listVersion),
              future: MustacheTemplateService.instance.listAll(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Available Templates',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...snapshot.data!.map((t) => ListTile(
                          dense: true,
                          leading: Icon(
                            t.source == TemplateSource.bundled
                                ? Icons.article_outlined
                                : Icons.edit_document,
                            size: 20,
                            color: t.source == TemplateSource.bundled
                                ? Colors.grey
                                : Colors.blue,
                          ),
                          title: Text(t.displayName),
                          subtitle: Text(
                            _sourceLabel(t.source),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: t.source != TemplateSource.bundled
                              ? IconButton(
                                  icon: const Icon(Icons.restore,
                                      size: 18, color: Colors.red),
                                  tooltip: 'Delete custom (restore bundled)',
                                  onPressed: () => _deleteCustom(t.key),
                                )
                              : null,
                          onTap: () => _loadTemplate(t.key),
                        )),
                    const Divider(height: 24),
                  ],
                );
              },
            ),

            const Text(
              'Tap a template above to load it into the editor, '
              'or import a .mustache file.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // --- TEMPLATE KEY ---
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Template Key',
                border: OutlineInputBorder(),
                helperText:
                    'Use a bundled key (yealink_t4x, polycom_vvx, cisco_88xx) '
                    'to override, or a new key for a custom brand.',
              ),
            ),
            const SizedBox(height: 15),

            // --- QUICK LOAD CHIPS ---
            const Text(
              'Load Bundled Template:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 8,
              children: MustacheTemplateService.bundledTemplates.keys
                  .map((key) => ActionChip(
                        label: Text(
                            MustacheTemplateService.displayNames[key] ?? key),
                        avatar: const Icon(Icons.phone_android, size: 16),
                        onPressed: () => _loadTemplate(key),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 15),

            // --- EDITOR ---
            TextField(
              controller: _contentController,
              maxLines: 15,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: 'Template Content (.mustache)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                fillColor: Color(0xFFF5F5F5),
                filled: true,
              ),
            ),
            const SizedBox(height: 20),

            // --- SAVE ---
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('SAVE CUSTOM TEMPLATE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(TemplateSource source) => switch (source) {
        TemplateSource.bundled => 'Bundled default',
        TemplateSource.customOverride => 'Custom override',
        TemplateSource.customNew => 'Custom (new brand)',
      };
}
