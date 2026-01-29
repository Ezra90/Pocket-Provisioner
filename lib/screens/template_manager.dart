import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart'; // Required for Export
import 'package:path_provider/path_provider.dart'; // Required to create temp file
import '../data/database_helper.dart';

class TemplateManagerScreen extends StatefulWidget {
  const TemplateManagerScreen({super.key});

  @override
  State<TemplateManagerScreen> createState() => _TemplateManagerScreenState();
}

class _TemplateManagerScreenState extends State<TemplateManagerScreen> {
  final _modelController = TextEditingController();
  final _contentController = TextEditingController();
  String _selectedType = 'text/plain';

  // --- IMPORT LOGIC ---
  Future<void> _importFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      String filename = result.files.single.name;

      setState(() {
        _contentController.text = content;
        
        // Auto-fill Model Name if empty
        if (_modelController.text.isEmpty) {
          _modelController.text = filename.split('.').first;
        }
        
        // Auto-detect type
        if (filename.toLowerCase().endsWith('xml')) {
          _selectedType = 'application/xml';
        } else {
          _selectedType = 'text/plain';
        }
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imported $filename"))
        );
      }
    }
  }

  // --- EXPORT LOGIC (New) ---
  Future<void> _exportFile() async {
    if (_modelController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a Model Name and Content to export"))
      );
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    
    // Determine extension
    String extension = _selectedType == 'application/xml' ? 'xml' : 'cfg';
    String fileName = "${_modelController.text}.$extension";

    // Write to temp file
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsString(_contentController.text);

    // Share
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Pocket Provisioner Template: ${_modelController.text}',
      sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _save() async {
    if (_modelController.text.isEmpty || _contentController.text.isEmpty) return;
    
    await DatabaseHelper.instance.saveTemplate(
      _modelController.text.trim(), 
      _selectedType, 
      _contentController.text
    );
    
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Template Saved to Database!")));
      Navigator.pop(context);
    }
  }

  // --- PRESETS ---
  void _loadPreset(String type) {
    if (type == 'Yealink') {
      _modelController.text = "T58W"; 
      _selectedType = 'text/plain';
      _contentController.text = '''#!version:1.0.0.1
## Custom Yealink Template
account.1.enable = 1
account.1.label = {{label}}
account.1.auth_name = {{extension}}
account.1.user_name = {{extension}}
account.1.password = {{secret}}
account.1.sip_server.1.address = {{sip_server_url}}
phone_setting.backgrounds = {{wallpaper_url}}
static.auto_provision.server.url = {{target_url}}
''';
    } else {
      _modelController.text = "VVX250";
      _selectedType = 'application/xml';
      _contentController.text = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PHONE_CONFIG>
  <REGISTRATION
    reg.1.displayName="{{label}}"
    reg.1.address="{{extension}}"
    reg.1.auth.userId="{{extension}}"
    reg.1.auth.password="{{secret}}"
    reg.1.server.1.address="{{sip_server_url}}"
  />
  <bg bg.color.bm.1.name="{{wallpaper_url}}" />
  <DEVICE device.prov.serverName="{{target_url}}" />
</PHONE_CONFIG>''';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Template Manager"),
        actions: [
          // IMPORT
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: "Import File",
            onPressed: _importFile,
          ),
          // EXPORT (Restored)
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Export/Share",
            onPressed: _exportFile,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              "Import, Edit, or Create handset templates.", 
              style: TextStyle(color: Colors.grey)
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: "Model Name (e.g. T33G)", 
                border: OutlineInputBorder(),
                helperText: "Must match the 'Model' in your CSV."
              ),
            ),
            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(labelText: "File Type", border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'text/plain', child: Text("Yealink (.cfg)")),
                DropdownMenuItem(value: 'application/xml', child: Text("Poly/Cisco (.xml)")),
              ], 
              onChanged: (v) => setState(() => _selectedType = v!)
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                const Text("Quick Load: "),
                TextButton(onPressed: () => _loadPreset('Yealink'), child: const Text("Yealink Base")),
                TextButton(onPressed: () => _loadPreset('Poly'), child: const Text("Poly Base")),
              ],
            ),

            TextField(
              controller: _contentController,
              maxLines: 15,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: "Template Content",
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                fillColor: Color(0xFFF5F5F5),
                filled: true,
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _save, 
                icon: const Icon(Icons.save), 
                label: const Text("SAVE TO DATABASE"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            )
          ],
        ),
      ),
    );
  }
}
