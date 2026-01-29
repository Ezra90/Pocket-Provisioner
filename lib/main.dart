import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/database_helper.dart';
import 'services/provisioning_server.dart';
import 'models/device.dart';

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

  /// Ensure we have Camera and Local Network permissions
  Future<void> _checkPermissions() async {
    await [Permission.camera, Permission.location].request();
  }

  // --- SETTINGS DIALOG ---
  void _openSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(text: prefs.getString('public_wallpaper_url') ?? '');

    showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text("Global Settings"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Public Wallpaper URL (Optional)", style: TextStyle(fontWeight: FontWeight.bold)),
            const Text("Use this for phones that don't store images locally (e.g. VVX1500).", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "https://my-site.com/logo.png",
                border: OutlineInputBorder()
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await prefs.setString('public_wallpaper_url', controller.text.trim());
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Settings Saved")));
            }, 
            child: const Text("Save")
          )
        ],
      )
    );
  }

  /// Generates sample data for demonstration
  Future<void> _importMockData() async {
    await DatabaseHelper.instance.clearAll();
    
    // Add Yealink Examples
    await DatabaseHelper.instance.insertDevice(Device(
        model: 'T58G', extension: '101', secret: '928374', label: 'Reception'));
    await DatabaseHelper.instance.insertDevice(Device(
        model: 'T58G', extension: '102', secret: '112233', label: 'Boardroom'));
    
    // Add Polycom Example
    await DatabaseHelper.instance.insertDevice(Device(
        model: 'VVX411', extension: '103', secret: '445566', label: 'Kitchen'));
        
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Success: Imported 3 Mock Devices."))
      );
    }
  }

  /// Toggles the Web Server on/off
  Future<void> _toggleServer() async {
    if (_isServerRunning) {
      // STOP
      setState(() {
        _serverStatus = "OFFLINE";
        _isServerRunning = false;
        _statusColor = Colors.red.shade100;
      });
      WakelockPlus.disable(); // Allow screen to sleep
    } else {
      // START
      try {
        String url = await ProvisioningServer().start();
        setState(() {
          _serverStatus = "ONLINE: $url";
          _isServerRunning = true;
          _statusColor = Colors.green.shade100;
        });
        WakelockPlus.enable(); // Keep screen awake for the server!
      } catch (e) {
        setState(() => _serverStatus = "ERROR: ${e.toString()}");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pocket Provisioner v0.0.2"),
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
            // --- SERVER STATUS CARD ---
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

            // --- ACTION BUTTONS ---
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _importMockData,
                    icon: const Icon(Icons.file_download),
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
            
            // --- SCANNER BUTTON ---
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

// --- SCANNER SCREEN ---
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

  /// Finds the next PENDING device from SQL
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
          // HUD (Heads Up Display)
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
          
          // Camera View
          Expanded(
            child: MobileScanner(
              onDetect: (capture) async {
                if (_isProcessing) return;
                
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;

                final String? rawMac = barcodes.first.rawValue;
                if (rawMac == null || rawMac.length < 10) return; // Basic validation

                setState(() => _isProcessing = true);
                
                // Clean the MAC
                String cleanMac = rawMac.replaceAll(':', '').toUpperCase();
                
                // Save to DB
                await DatabaseHelper.instance.assignMac(_target!.id!, cleanMac);
                
                // Feedback
                if(mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Matched $cleanMac to ${_target!.extension}"),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    )
                  );
                }
                
                // Advance
                _loadNextTarget();
              },
            ),
          ),
        ],
      ),
    );
  }
}
