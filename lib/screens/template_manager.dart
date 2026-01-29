import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  Future<void> _importFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      String filename = result.files.single.name;

      setState(() {
        _contentController.text = content;
        
        if (_modelController.text.isEmpty) {
          _modelController.text = filename.split('.').first;
        }
        
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

  Future<void> _save() async {
    if (_modelController.text.isEmpty || _contentController.text.isEmpty) return;
    
    await DatabaseHelper.instance.saveTemplate(
      _modelController.text.trim(), 
      _selectedType, 
      _contentController.text
    );
    
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Template Saved!")));
      Navigator.pop(context);
    }
  }

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
account.1.sip_server.1.address = {{local_ip}}
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
    reg.1.server.1.address="{{local_ip}}"
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
        title: const Text("Add New Template"),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: "Import from File",
            onPressed: _importFile,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              "Import a template file or create one from scratch.", 
              style: TextStyle(color: Colors.grey)
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: "Model Name (e.g. T33G)", 
                border: OutlineInputBorder(),
                helperText: "This must match the 'Model' in your CSV exactly."
              ),
            ),
            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(labelText: "Template Type", border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'text/plain', child: Text("Yealink / Text")),
                DropdownMenuItem(value: 'application/xml', child: Text("Polycom / XML")),
              ], 
              onChanged: (v) => setState(() => _selectedType = v!)
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                const Text("Presets: "),
                TextButton(onPressed: () => _loadPreset('Yealink'), child: const Text("Yealink Base")),
                TextButton(onPressed: () => _loadPreset('Poly'), child: const Text("Polycom Base")),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _importFile, 
                  icon: const Icon(Icons.folder_open),
                  label: const Text("Load File"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                ),
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
                label: const Text("SAVE TEMPLATE TO DATABASE"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            )
          ],
        ),
      ),
    );
  }
}
