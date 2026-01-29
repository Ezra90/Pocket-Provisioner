import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'data/database_helper.dart';
import 'services/provisioning_server.dart';
import 'services/wallpaper_service.dart'; // Import New Service
import 'models/device.dart';
import 'screens/template_manager.dart';
import 'screens/button_layout_editor.dart';
import 'data/device_templates.dart';

void main() {
  runApp(const MaterialApp(
    title: 'Pocket Provisioner',
    debugShowCheckedModeBanner: false,
    home: DashboardScreen(),
  ));
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _serverStatus = "OFFLINE";
  bool _isServerRunning = false;
  Color _statusColor = Colors.red.shade100;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await [Permission.camera, Permission.location].request();
  }

  // --- WALLPAPER PICKER DIALOG ---
  void _openWallpaperTools(BuildContext context, Function onSave) {
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;
    
    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final spec = DeviceTemplates.getSpecForModel(selectedModel);
          
          return AlertDialog(
            title: const Text("Smart Wallpaper Tool"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("1. Select Target Model Family:"),
                DropdownButton<String>(
                  value: selectedModel,
                  isExpanded: true,
                  items: DeviceTemplates.wallpaperSpecs.keys.map((k) {
                    return DropdownMenuItem(value: k, child: Text(k));
                  }).toList(),
                  onChanged: (v) => setState(() => selectedModel = v!),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Required Size: ${spec.width} x ${spec.height} px", style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("Type: ${spec.label}", style: const TextStyle(fontSize: 12)),
                      const Text("Format: PNG (Auto-Converted)", style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text("2. Upload & Auto-Resize:"),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.image),
                    label: const Text("Pick Image from Gallery"),
                    onPressed: () async {
                      // 1. Pick
                      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                      if (result == null) return;

                      // 2. Process
                      try {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Processing Image...")));
                        }
                        
                        await WallpaperService.processAndSaveWallpaper(result.files.single.path!, spec);
                        
                        // 3. Save URL to Settings (Local path marker)
                        // We set it to empty string or a marker to tell the server "Use Local"
                        // But strictly, we update the SharedPref so the Main UI reflects it
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('public_wallpaper_url', "LOCAL_HOSTED"); 
                        
                        if (mounted) {
                          Navigator.pop(context); // Close Wallpaper Dialog
                          onSave(); // Refresh Main Settings Dialog
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallpaper Resized & Saved!")));
                        }
                      } catch (e) {
                        print(e);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    },
                  ),
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))
            ],
          );
        }
      )
    );
  }

  void _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final wallpaperController = TextEditingController(text: prefs.getString('public_wallpaper_url') ?? '');
    final targetUrlController = TextEditingController(text: prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget);

    if(!mounted) return;

    showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text("Global Settings"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Target Server (The Hop)", style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(
                controller: targetUrlController,
                decoration: const InputDecoration(hintText: "http://provisioning.server.com"),
              ),
              const SizedBox(height: 20),
              
              const Text("Wallpaper Source", style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wallpaperController,
                      decoration: const InputDecoration(hintText: "URL or LOCAL_HOSTED", labelText: "Current Source"),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high, color: Colors.blue),
                    tooltip: "Open Smart Resizer",
                    onPressed: () => _openWallpaperTools(context, () {
                      // Refresh the text field after tools close
                      wallpaperController.text = prefs.getString('public_wallpaper_url') ?? '';
                    }),
                  )
                ],
              ),
              
              const Divider(height: 30),
              ListTile(
                leading: const Icon(Icons.file_copy, color: Colors.blue),
                title: const Text("Templates"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const TemplateManagerScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_on, color: Colors.green),
                title: const Text("Button Layouts"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const ButtonLayoutEditorScreen()));
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await prefs.setString('public_wallpaper_url', wallpaperController.text.trim());
              await prefs.setString('target_provisioning_url', targetUrlController.text.trim());
              if(mounted) Navigator.pop(context);
            }, 
            child: const Text("Save")
          )
        ],
      )
    );
  }

  Future<void> _importCSV() async {
    // ... (Import CSV logic remains unchanged from previous, kept brevity) ...
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    if (result == null) return;
    try {
      final File file = File(result.files.single.path!);
      final String rawContent = await file.readAsString();
      List<List<dynamic>> rows = const CsvToListConverter().convert(rawContent, eol: "\n");
      if (rows.isEmpty) throw "Empty file";
      List<dynamic> headers = rows[0].map((e) => e.toString().toLowerCase().trim()).toList();
      int extIndex = headers.indexWhere((h) => h.contains('extension') || h == 'ext' || h.contains('user'));
      int passIndex = headers.indexWhere((h) => h.contains('secret') || h.contains('pass'));
      int nameIndex = headers.indexWhere((h) => h.contains('label') || h.contains('name') || h.contains('description'));
      int modelIndex = headers.indexWhere((h) => h.contains('model') || h.contains('type'));
      int macIndex = headers.indexWhere((h) => h.contains('mac'));
      if (extIndex == -1) throw "Could not find 'Extension' column";
      int count = 0;
      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.length <= extIndex) continue;
        String extension = row[extIndex].toString();
        String secret = (passIndex != -1 && row.length > passIndex) ? row[passIndex].toString() : "1234";
        String label = (nameIndex != -1 && row.length > nameIndex) ? row[nameIndex].toString() : extension;
        String model = (modelIndex != -1 && row.length > modelIndex) ? row[modelIndex].toString() : "T58G"; 
        String? mac = (macIndex != -1 && row.length > macIndex) ? row[macIndex].toString() : null;
        if (mac != null) { mac = mac.replaceAll(':', '').toUpperCase(); if (mac.length < 10) mac = null; }
        await DatabaseHelper.instance.insertDevice(Device(model: model, extension: extension, secret: secret, label: label, macAddress: mac, status: mac != null ? 'READY' : 'PENDING'));
        count++;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Imported $count devices")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _toggleServer() async {
    if (_isServerRunning) {
      await ProvisioningServer().stop();
      setState(() { _serverStatus = "OFFLINE"; _isServerRunning = false; _statusColor = Colors.red.shade100; });
      WakelockPlus.disable(); 
    } else {
      try {
        String url = await ProvisioningServer().start();
        setState(() { _serverStatus = "ONLINE: $url"; _isServerRunning = true; _statusColor = Colors.green.shade100; });
        WakelockPlus.enable(); 
      } catch (e) {
        setState(() => _serverStatus = "ERROR: ${e.toString()}");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pocket Provisioner"),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: _statusColor,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.router, size: 48),
                    const SizedBox(height: 10),
                    Text(_serverStatus, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_isServerRunning)
                      const Text("Set Router Option 66 to this URL", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: ElevatedButton.icon(onPressed: _importCSV, icon: const Icon(Icons.upload), label: const Text("Import CSV"))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: _toggleServer, 
                  icon: Icon(_isServerRunning ? Icons.stop : Icons.play_arrow), 
                  label: Text(_isServerRunning ? "Stop" : "Start"),
                  style: ElevatedButton.styleFrom(backgroundColor: _isServerRunning ? Colors.red : Colors.green, foregroundColor: Colors.white)
                )),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 100,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ScannerScreen())),
                icon: const Icon(Icons.qr_code_scanner, size: 30),
                label: const Text("START SCANNING", style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ... ScannerScreen class (Unchanged) ...
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  Device? _target;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadNextTarget();
  }

  Future<void> _loadNextTarget() async {
    final next = await DatabaseHelper.instance.getNextPendingDevice();
    setState(() {
      _target = next;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_target == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Complete")),
        body: const Center(child: Text("All Devices Assigned!", style: TextStyle(fontSize: 24))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Scan Barcode")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.blue,
            child: Column(
              children: [
                Text("${_target!.extension} - ${_target!.label}", style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                Text(_target!.model, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) async {
                if (_isProcessing) return;
                final String? rawMac = capture.barcodes.first.rawValue;
                if (rawMac == null || rawMac.length < 10) return;

                setState(() => _isProcessing = true);
                String cleanMac = rawMac.replaceAll(':', '').toUpperCase();
                await DatabaseHelper.instance.assignMac(_target!.id!, cleanMac);
                
                if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Matched $cleanMac"), backgroundColor: Colors.green));
                _loadNextTarget();
              },
            ),
          ),
        ],
      ),
    );
  }
}
