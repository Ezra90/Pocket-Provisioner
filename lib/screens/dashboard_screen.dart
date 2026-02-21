import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/database_helper.dart';
import '../services/mustache_renderer.dart';
import '../services/mustache_template_service.dart';
import '../services/provisioning_server.dart';
import '../services/button_layout_service.dart';
import '../models/button_key.dart';
import '../models/device.dart';
import 'settings_screen.dart';
import 'scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _serverStatus = "OFFLINE";
  bool _isServerRunning = false;
  Color _statusColor = Colors.red.shade100;
  final String _appVersion = "v0.0.4";

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final statuses = await [
      Permission.camera, 
      Permission.location, // Critical for getting Local IP on Android
    ].request();
    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera and location permissions are required for full functionality.")),
      );
    }
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

      List<dynamic> headers = rows[0].map((e) => e.toString().toLowerCase().trim()).toList();
      
      // Smart Header Matching
      int extIndex = headers.indexWhere((h) => h.contains('device username') || h.contains('extension') || h == 'user' || h == 'username');
      int passIndex = headers.indexWhere((h) => h.contains('dms password') || h.contains('secret') || h.contains('pass'));
      int nameIndex = headers.indexWhere((h) => h == 'name' || h.contains('device name') || h.contains('label') || h.contains('description'));
      int modelIndex = headers.indexWhere((h) => h.contains('device type') || h.contains('model'));
      int phoneIndex = headers.indexWhere((h) => h.contains('user id') || h.contains('phone') || h == 'dn');
      int macIndex = headers.indexWhere((h) => h.contains('mac'));

      if (extIndex == -1) throw "Could not find 'Device Username' or 'Extension' column";

      int count = 0;
      final List<Device> devicesToInsert = [];
      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.length <= extIndex) continue;

        String extension = row[extIndex].toString().trim();
        String secret = (passIndex != -1 && row.length > passIndex) ? row[passIndex].toString().trim() : "1234";
        String model = (modelIndex != -1 && row.length > modelIndex) ? row[modelIndex].toString().trim() : "T58G"; 
        
        String baseName = (nameIndex != -1 && row.length > nameIndex) ? row[nameIndex].toString().trim() : extension;
        String phoneNumber = (phoneIndex != -1 && row.length > phoneIndex) ? row[phoneIndex].toString().trim() : "";
        String finalLabel = phoneNumber.isNotEmpty ? "$phoneNumber - $baseName" : baseName;

        String? mac = (macIndex != -1 && row.length > macIndex) ? row[macIndex].toString() : null;
        if (mac != null) {
          mac = mac.replaceAll(':', '').toUpperCase();
          if (mac.length < 10) mac = null; 
        }

        devicesToInsert.add(Device(
          model: model,
          extension: extension,
          secret: secret,
          label: finalLabel,
          macAddress: mac,
          status: mac != null ? 'READY' : 'PENDING'
        ));
        count++;
      }

      await DatabaseHelper.instance.insertDevices(devicesToInsert);

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

  Future<void> _generateAllConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sipServer = prefs.getString('sip_server_address') ?? '';
      final provisioningUrl = prefs.getString('target_provisioning_url') ?? '';
      final wallpaperUrl = prefs.getString('public_wallpaper_url') ?? '';
      
      final ntpServer = prefs.getString('ntp_server') ?? '';
      final timezone = prefs.getString('timezone_offset') ?? '';
      final adminPassword = prefs.getString('admin_password') ?? '';
      final voiceVlanId = prefs.getString('voice_vlan_id') ?? '';

      // Resolve local wallpaper references to actual server URLs
      String resolvedWallpaperUrl = wallpaperUrl;
      if (wallpaperUrl == 'LOCAL_HOSTED' || wallpaperUrl.startsWith('LOCAL:')) {
        final serverUrl = ProvisioningServer.serverUrl;
        if (serverUrl != null) {
          if (wallpaperUrl.startsWith('LOCAL:')) {
            final filename = wallpaperUrl.substring('LOCAL:'.length); // strip "LOCAL:"
            resolvedWallpaperUrl = '$serverUrl/media/$filename';
          } else {
            // Legacy LOCAL_HOSTED — try to find any wallpaper in the media dir
            resolvedWallpaperUrl = '$serverUrl/media/custom_bg.png';
          }
        }
      }

      final carryOver = await ButtonLayoutService.getCarryOverSettings();
      final carryOverLayout = carryOver['button_layout'] ?? false;

      final devices = await DatabaseHelper.instance.getReadyDevices();

      if (devices.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No READY devices found. Import a CSV and scan barcodes first.")),
          );
        }
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory(p.join(appDir.path, 'generated_configs'));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Build a carry-over layout cache keyed by model (only when flag is on)
      final Map<String, List<ButtonKey>> layoutCache = {};

      int generated = 0;
      final List<String> carriedOverModels = [];

      for (final device in devices) {
        if (device.macAddress == null || device.macAddress!.isEmpty) continue;

        List<ButtonKey>? lineKeys;
        if (carryOverLayout) {
          // Load layout once per model and cache it
          if (!layoutCache.containsKey(device.model)) {
            layoutCache[device.model] =
                await ButtonLayoutService.getLayoutForModel(device.model);
          }
          final baseLayout = layoutCache[device.model]!;
          if (baseLayout.isNotEmpty) {
            // Deep-copy keys so per-device overrides don't mutate the cache
            lineKeys = baseLayout.map((k) => k.clone()).toList();

            // Apply per-device label overrides saved during scanning
            final overrides = await ButtonLayoutService.getLabelOverrides(device.macAddress!);
            if (overrides.isNotEmpty) {
              for (final key in lineKeys) {
                final override = overrides[key.id.toString()];
                if (override != null) key.label = override;
              }
            }
            if (!carriedOverModels.contains(device.model)) {
              carriedOverModels.add(device.model);
            }
          }
        }

        final templateKey = MustacheRenderer.resolveTemplateKey(device.model);
        final variables = MustacheRenderer.buildVariables(
          macAddress: device.macAddress!,
          extension: device.extension,
          displayName: device.label,
          secret: device.secret,
          model: device.model,
          sipServer: sipServer,
          provisioningUrl: provisioningUrl,
          wallpaperUrl: resolvedWallpaperUrl,
          lineKeys: lineKeys,
          ntpServer: ntpServer.isNotEmpty ? ntpServer : null,
          timezone: timezone.isNotEmpty ? timezone : null,
          adminPassword: adminPassword.isNotEmpty ? adminPassword : null,
          voiceVlanId: voiceVlanId.isNotEmpty ? voiceVlanId : null,
        );
        final rendered = await MustacheRenderer.render(templateKey, variables);
        final contentType = MustacheTemplateService.contentTypes[templateKey] ?? 'text/plain';
        final ext = contentType == 'application/xml' ? 'xml' : 'cfg';
        final mac = device.macAddress!.replaceAll(':', '').toUpperCase();
        final file = File(p.join(outputDir.path, '$mac.$ext'));
        await file.writeAsString(rendered);
        generated++;
      }

      if (mounted) {
        final carryMsg = carryOverLayout && carriedOverModels.isNotEmpty
            ? " (layout carried over: ${carriedOverModels.join(', ')})"
            : "";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Generated configs for $generated devices!$carryMsg")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error generating configs: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleServer() async {
    if (_isServerRunning) {
      await ProvisioningServer.instance.stop();
      setState(() {
        _serverStatus = "OFFLINE";
        _isServerRunning = false;
        _statusColor = Colors.red.shade100;
      });
      WakelockPlus.disable(); 
    } else {
      try {
        String url = await ProvisioningServer.instance.start();
        setState(() {
          _serverStatus = "ONLINE: $url";
          _isServerRunning = true;
          _statusColor = Colors.green.shade100;
        });
        WakelockPlus.enable(); 
      } catch (e) {
        setState(() => _serverStatus = "ERROR: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Pocket Provisioner $_appVersion"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen())),
          )
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
                    Text(_serverStatus, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_isServerRunning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Set Router DHCP Option 66 to this URL", style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Router Configuration Info"),
                                    content: const Text("Don't forget to configure Option 66 on your local router to point to this URL. Also, ensure the handset is factory reset so it pulls the configuration on boot."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Got it"))
                                    ],
                                  )
                                );
                              },
                              child: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                            )
                          ],
                        ),
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generateAllConfigs,
                icon: const Icon(Icons.build_circle),
                label: const Text("Generate All Configs"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
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
