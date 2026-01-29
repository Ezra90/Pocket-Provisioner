import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:path_provider/path_provider.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart'; // Import this to access live templates

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

  // --- EXPORT LOGIC ---
  Future<void> _exportFile() async {
    if (_modelController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a Model Name and Content to export"))
      );
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    
    String extension = _selectedType == 'application/xml' ? 'xml' : 'cfg';
    String fileName = "${_modelController.text}.$extension";

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    await file.writeAsString(_contentController.text);

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

  // --- LOAD LIVE APP DEFAULTS ---
  void _loadBaseTemplate(String type) {
    String content = "";
    if (type == 'Yealink') {
      _modelController.text = "T54W_Custom";
      _selectedType = 'text/plain';
      // Pulls the ACTUAL source code template
      content = DeviceTemplates.fallbackYealinkTemplate;
    } else if (type == 'Poly') {
      _modelController.text = "EdgeE450_Custom";
      _selectedType = 'application/xml';
      content = DeviceTemplates.fallbackPolycomTemplate;
    } else if (type == 'Cisco') {
      _modelController.text = "8851_Custom";
      _selectedType = 'application/xml';
      content = DeviceTemplates.fallbackCiscoTemplate;
    }
    
    _contentController.text = content;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Template Manager"),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: "Import File",
            onPressed: _importFile,
          ),
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
              "Load a base template to modify, or import a new one.", 
              style: TextStyle(color: Colors.grey)
            ),
            const SizedBox(height: 20),
            
            // Model Name Input
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: "Model Name (e.g. T33G)", 
                border: OutlineInputBorder(),
                helperText: "Must match the 'Model' column in your CSV exactly."
              ),
            ),
            const SizedBox(height: 15),

            // File Type Selector
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

            // Quick Load Buttons
            const Text("Load Base Template:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Wrap(
              spacing: 10,
              children: [
                ActionChip(
                  label: const Text("Yealink"),
                  avatar: const Icon(Icons.phone_android, size: 16),
                  onPressed: () => _loadBaseTemplate('Yealink'),
                ),
                ActionChip(
                  label: const Text("Poly"),
                  avatar: const Icon(Icons.phone, size: 16),
                  onPressed: () => _loadBaseTemplate('Poly'),
                ),
                ActionChip(
                  label: const Text("Cisco"),
                  avatar: const Icon(Icons.router, size: 16),
                  onPressed: () => _loadBaseTemplate('Cisco'),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Editor Area
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

            // Save Button
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
