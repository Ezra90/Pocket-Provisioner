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
import 'services/wallpaper_service.dart';
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
    await [
      Permission.camera, 
      Permission.location, // Critical for Android Wi-Fi IP
    ].request();
  }

  // --- WALLPAPER RESIZER DIALOG ---
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
              children: [
                DropdownButton<String>(
                  value: selectedModel,
                  isExpanded: true,
                  items: DeviceTemplates.wallpaperSpecs.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                  onChanged: (v) => setState(() => selectedModel = v!),
                ),
                const SizedBox(height: 10),
                Text("Required: ${spec.width}x${spec.height} ${spec.format.toUpperCase()}"),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (result == null) return;
                    await WallpaperService.processAndSaveWallpaper(result.files.single.path!, spec);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('public_wallpaper_url', "LOCAL_HOSTED"); 
                    if (mounted) {
                      Navigator.pop(context);
                      onSave();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallpaper Processed!")));
                    }
                  }, 
                  child: const Text("Pick & Resize Image")
                )
              ],
            ),
          );
        }
      )
    );
  }

  // --- SETTINGS DIALOG ---
  void _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final wallpaperController = TextEditingController(text: prefs.getString('public_wallpaper_url') ?? '');
    final targetUrlController = TextEditingController(text: prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget);
    final sipServerController = TextEditingController(text: prefs.getString('sip_server_address') ?? '');

    String refModel = DeviceTemplates.wallpaperSpecs.keys.first;

    if(!mounted) return;

    showDialog(
      context: context, 
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final spec = DeviceTemplates.getSpecForModel(refModel);
          
          return AlertDialog(
            title: const Text("Global Settings"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("1. Target Provisioning (The Hop)", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text("URL where phone goes NEXT (Telstra/3CX).", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  TextField(
                    controller: targetUrlController,
                    decoration: const InputDecoration(hintText: "http://provisioning.server.com"),
                  ),
                  const SizedBox(height: 15),

                  const Text("2. Primary SIP Server", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text("Leave BLANK for Telstra/Hop. Enter IP for Manual/FreePBX.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  TextField(
                    controller: sipServerController,
                    decoration: const InputDecoration(hintText: "e.g. 192.168.1.10"),
                  ),
                  const SizedBox(height: 15),
                  
                  const Text("3. Wallpaper Source", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text("Spec Reference:", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  DropdownButton<String>(
                    value: refModel,
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    items: DeviceTemplates.wallpaperSpecs.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                    onChanged: (v) => setState(() => refModel = v!),
                  ),
                  Text("Required: ${spec.width}x${spec.height} ${spec.format.toUpperCase()}", style: const TextStyle(fontSize: 12, color: Colors.blue)),
                  
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: wallpaperController,
                          decoration: const InputDecoration(hintText: "URL or LOCAL_HOSTED"),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.auto_fix_high, color: Colors.blue),
                        onPressed: () => _openWallpaperTools(context, () {
                          wallpaperController.text = prefs.getString('public_wallpaper_url') ?? '';
                        }),
                      )
                    ],
                  ),
                  
                  const Divider(height: 20),
                  ListTile(
                    title: const Text("Manage Templates"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const TemplateManagerScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("Button Layouts"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                  await prefs.setString('sip_server_address', sipServerController.text.trim());
                  if(mounted) Navigator.pop(context);
                }, 
                child: const Text("Save")
              )
            ],
          );
        }
      )
    );
  }

  // --- SMART CSV IMPORT ---
  Future<void> _importCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );

    if (result == null) return;

    try {
      final File file = File(result.files.single.path!);
      final String rawContent = await file.readAsString();
      
      List<List<dynamic>> rows = const CsvToListConverter().convert(rawContent, eol: "\n");
      if (rows.isEmpty) throw "Empty file";

      // Normalize headers to lowercase
      List<dynamic> headers = rows[0].map((e) => e.toString().toLowerCase().trim()).toList();
      
      // 1. EXTENSION: "Device username" (Telstra) or "extension" (FreePBX)
      int extIndex = headers.indexWhere((h) => 
        h.contains('device username') || h.contains('extension') || h == 'user' || h == 'username');
      
      // 2. SECRET: "DMS password" (Telstra) or "secret" (FreePBX)
      int passIndex = headers.indexWhere((h) => 
        h.contains('dms password') || h.contains('secret') || h.contains('pass'));
      
      // 3. NAME: "Device name" or "Name" or "Label"
      int nameIndex = headers.indexWhere((h) => 
        h == 'name' || h.contains('device name') || h.contains('label') || h.contains('description'));
      
      // 4. MODEL: "Device type" (Telstra) or "Model"
      int modelIndex = headers.indexWhere((h) => 
        h.contains('device type') || h.contains('model'));
      
      // 5. PHONE/USER ID: "User ID" (Telstra) or "Phone Number" -> Used for Label
      int phoneIndex = headers.indexWhere((h) => 
        h.contains('user id') || h.contains('phone') || h == 'dn');

      int macIndex = headers.indexWhere((h) => h.contains('mac')); // Optional

      if (extIndex == -1) throw "Could not find 'Device Username' or 'Extension' column";

      int count = 0;
      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.length <= extIndex) continue; // Skip incomplete rows

        // --- Data Extraction ---
        String extension = row[extIndex].toString().trim();
        String secret = (passIndex != -1 && row.length > passIndex) ? row[passIndex].toString().trim() : "1234";
        String model = (modelIndex != -1 && row.length > modelIndex) ? row[modelIndex].toString().trim() : "T58G"; 
        
        // --- Label Generation Logic ---
        String baseName = (nameIndex != -1 && row.length > nameIndex) ? row[nameIndex].toString().trim() : extension;
        String phoneNumber = (phoneIndex != -1 && row.length > phoneIndex) ? row[phoneIndex].toString().trim() : "";
        
        // Format: "0712345678 - Reception" OR just "Reception"
        String finalLabel = phoneNumber.isNotEmpty ? "$phoneNumber - $baseName" : baseName;

        String? mac = (macIndex != -1 && row.length > macIndex) ? row[macIndex].toString() : null;
        if (mac != null) {
          mac = mac.replaceAll(':', '').toUpperCase();
          if (mac.length < 10) mac = null; 
        }

        await DatabaseHelper.instance.insertDevice(Device(
          model: model,
          extension: extension, // This is the Auth Username (1635...)
          secret: secret,       // This is the Auth Password
          label: finalLabel,    // This shows on the screen
          macAddress: mac,
          status: mac != null ? 'READY' : 'PENDING'
        ));
        count++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imported $count devices!"))
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Import Failed: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _toggleServer() async {
    if (_isServerRunning) {
      await ProvisioningServer().stop();
      setState(() {
        _serverStatus = "OFFLINE";
        _isServerRunning = false;
        _statusColor = Colors.red.shade100;
      });
      WakelockPlus.disable(); 
    } else {
      try {
        String url = await ProvisioningServer().start();
        setState(() {
          _serverStatus = "ONLINE: $url";
          _isServerRunning = true;
          _statusColor = Colors.green.shade100;
        });
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
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.router, size: 48, color: Colors.black54),
                    const SizedBox(height: 10),
                    Text(_serverStatus, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_isServerRunning)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text("Set Router DHCP Option 66 to this URL", style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _importCSV,
                    icon: const Icon(Icons.file_upload),
                    label: const Text("Import CSV"),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _toggleServer,
                    icon: Icon(_isServerRunning ? Icons.stop_circle : Icons.play_circle),
                    label: Text(_isServerRunning ? "Stop Server" : "Start Server"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: _isServerRunning ? Colors.redAccent : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            SizedBox(
              height: 120,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const ScannerScreen()));
                },
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 40, color: Colors.white),
                    SizedBox(height: 8),
                    Text("START SCANNING", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("Auto-Advance Mode", style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ... ScannerScreen class remains unchanged ...
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
        appBar: AppBar(title: const Text("Job Complete")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              const Text("All Devices Assigned!", style: TextStyle(fontSize: 24)),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text("Return to Dashboard")
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Scan Barcode")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Colors.blueAccent,
            child: Column(
              children: [
                const Text("SCANNING FOR:", style: TextStyle(color: Colors.white70, letterSpacing: 1.5)),
                const SizedBox(height: 5),
                Text(
                  "${_target!.extension}",
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                Text(
                  _target!.label, // NOW SHOWS "0712345678 - Reception"
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                Text("Model: ${_target!.model}", style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          
          Expanded(
            child: MobileScanner(
              onDetect: (capture) async {
                if (_isProcessing) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final String? rawMac = barcodes.first.rawValue;
                if (rawMac == null || rawMac.length < 10) return;

                setState(() => _isProcessing = true);
                String cleanMac = rawMac.replaceAll(':', '').toUpperCase();
                await DatabaseHelper.instance.assignMac(_target!.id!, cleanMac);
                
                if(mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Matched $cleanMac to ${_target!.label}"),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    )
                  );
                }
                _loadNextTarget();
              },
            ),
          ),
        ],
      ),
    );
  }
}
