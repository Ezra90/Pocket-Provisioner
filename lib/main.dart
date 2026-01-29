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
import 'models/device.dart';
import 'screens/template_manager.dart';
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

  // --- SETTINGS DIALOG ---
  void _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load saved settings or use defaults
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Target URL (The most important setting)
              const Text("Target Provisioning Server (The Hop)", style: TextStyle(fontWeight: FontWeight.bold)),
              const Text("Where phones go after initial setup (Telstra/3CX/FreePBX).", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 5),
              TextField(
                controller: targetUrlController,
                decoration: const InputDecoration(
                  hintText: "http://provisioning.server.com/cfg",
                  border: OutlineInputBorder()
                ),
              ),
              const SizedBox(height: 15),

              // 2. Wallpaper URL
              const Text("Public Wallpaper URL", style: TextStyle(fontWeight: FontWeight.bold)),
              const Text("For phones that don't cache images locally.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 5),
              TextField(
                controller: wallpaperController,
                decoration: const InputDecoration(
                  hintText: "https://my-site.com/logo.png",
                  border: OutlineInputBorder()
                ),
              ),
              
              const Divider(height: 30),
              
              // 3. Template Manager
              ListTile(
                leading: const Icon(Icons.file_copy, color: Colors.blue),
                title: const Text("Manage Templates"),
                subtitle: const Text("Add/Import new phone models"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const TemplateManagerScreen()));
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
              
              if(mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved")));
              }
            }, 
            child: const Text("Save")
          )
        ],
      )
    );
  }

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

      // SMART MAPPING
      List<dynamic> headers = rows[0].map((e) => e.toString().toLowerCase().trim()).toList();
      
      int extIndex = headers.indexWhere((h) => h.contains('extension') || h == 'ext' || h.contains('user'));
      int passIndex = headers.indexWhere((h) => h.contains('secret') || h.contains('pass'));
      int nameIndex = headers.indexWhere((h) => h.contains('label') || h.contains('name') || h.contains('description'));
      int modelIndex = headers.indexWhere((h) => h.contains('model') || h.contains('type'));
      int macIndex = headers.indexWhere((h) => h.contains('mac'));

      if (extIndex == -1) throw "Could not find 'Extension' or 'Username' column";

      int count = 0;
      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.length <= extIndex) continue;

        String extension = row[extIndex].toString();
        String secret = (passIndex != -1 && row.length > passIndex) ? row[passIndex].toString() : "1234";
        String label = (nameIndex != -1 && row.length > nameIndex) ? row[nameIndex].toString() : extension;
        String? mac = (macIndex != -1 && row.length > macIndex) ? row[macIndex].toString() : null;
        String model = (modelIndex != -1 && row.length > modelIndex) ? row[modelIndex].toString() : "T58G"; 

        if (mac != null) {
          mac = mac.replaceAll(':', '').toUpperCase();
          if (mac.length < 10) mac = null; 
        }

        await DatabaseHelper.instance.insertDevice(Device(
          model: model,
          extension: extension,
          secret: secret,
          label: label,
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
        title: const Text("Pocket Provisioner v0.0.3"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings)
        ],
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
                    const Text("SERVER STATUS", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_serverStatus, style: const TextStyle(fontSize: 16, fontFamily: 'Monospace')),
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
                  "${_target!.extension} - ${_target!.label}",
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
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
                      content: Text("Matched $cleanMac to ${_target!.extension}"),
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
