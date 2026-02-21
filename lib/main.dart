import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'data/database_helper.dart';
import 'services/mustache_renderer.dart';
import 'services/mustache_template_service.dart';
import 'services/provisioning_server.dart';
import 'services/button_layout_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'services/wallpaper_service.dart';
import 'models/button_key.dart';
import 'models/device.dart';
import 'screens/template_manager.dart';
import 'screens/button_layout_editor.dart';
import 'screens/hosted_files_screen.dart';
import 'screens/media_manager_screen.dart';
import 'data/device_templates.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  // --- HELPER: DMS/EPM EXPLANATION DIALOG ---
  void _showDmsHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("What is DMS / EPM?"),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Endpoint Manager (EPM)", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("A comprehensive tool for configuration, security, firmware updates, and deployment. Widely used in VoIP environments (e.g., FreePBX Endpoint Manager) to manage desk phones."),
              SizedBox(height: 10),
              Text("DMS (Device Management System)", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("Similar to EPM, often used by specific carriers for initial device provisioning."),
              SizedBox(height: 10),
              Divider(),
              Text("The 'Target Server' setting tells the phone where to go after this app applies the initial wallpaper and buttons.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Got it"))
        ],
      ),
    );
  }

  // --- WALLPAPER RESIZER DIALOG ---
  void _openWallpaperTools(BuildContext context, Function onSave) {
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;
    final nameController = TextEditingController();
    
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
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Name (required)',
                    hintText: 'e.g. BunningsT4X',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
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
                    final customName = nameController.text.trim();
                    if (customName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please enter a custom name first")));
                      return;
                    }
                    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (result == null) return;
                    final resizedFilename = await WallpaperService.processAndSaveWallpaper(
                        result.files.single.path!, spec, customName);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('public_wallpaper_url', 'LOCAL:$resizedFilename');
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

    // Load carry-over preferences before opening the dialog
    final carryOver = await ButtonLayoutService.getCarryOverSettings();
    bool carryOverLayout = carryOver['button_layout'] ?? false;
    bool carryOverWallpaper = carryOver['wallpaper'] ?? false;
    bool carryOverRingtone = carryOver['ringtone'] ?? false;
    bool carryOverVolume = carryOver['volume'] ?? false;

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
                  // 1. DMS / EPM SECTION
                  Row(
                    children: [
                      const Text("1. Target DMS / EPM Server", style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.help_outline, size: 18, color: Colors.grey),
                        onPressed: () => _showDmsHelp(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const Text("URL where phone goes NEXT.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  TextField(
                    controller: targetUrlController,
                    decoration: const InputDecoration(
                      hintText: "http://polydms.digitalbusiness.telstra.com/dms/bootstrap", // Example kept for clarity
                      helperText: "e.g. Carrier DMS or EPM URL",
                      helperStyle: TextStyle(fontSize: 10, color: Colors.grey)
                    ),
                  ),
                  const SizedBox(height: 15),

                  // 2. SIP SERVER SECTION
                  const Text("2. Primary SIP Server IP", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text("Leave BLANK for DMS/Cloud. Enter IP for Local PBX.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  TextField(
                    controller: sipServerController,
                    decoration: const InputDecoration(hintText: "e.g. 192.168.1.10"),
                  ),
                  const SizedBox(height: 15),
                  
                  // 3. WALLPAPER SECTION
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

                  const Divider(height: 24),

                  // 4. CARRY-OVER SETTINGS
                  const Text("4. Carry-Over Settings", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                    "Tick settings to reuse across all handsets in a batch. "
                    "Per-device data (extension, secret, MAC, label) is never carried over.",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    dense: true,
                    title: const Text("Button Layout"),
                    subtitle: const Text("Reuse the same key layout for every handset"),
                    value: carryOverLayout,
                    onChanged: (v) => setState(() => carryOverLayout = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text("Wallpaper"),
                    subtitle: const Text("Apply the same wallpaper to every handset"),
                    value: carryOverWallpaper,
                    onChanged: (v) => setState(() => carryOverWallpaper = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text("Ringtone"),
                    subtitle: const Text("Apply the same ringtone to every handset"),
                    value: carryOverRingtone,
                    onChanged: (v) => setState(() => carryOverRingtone = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text("Volume"),
                    subtitle: const Text("Apply the same volume settings to every handset"),
                    value: carryOverVolume,
                    onChanged: (v) => setState(() => carryOverVolume = v),
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
                  ListTile(
                    title: const Text("Hosted Files"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const HostedFilesScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("Media Manager"),
                    subtitle: const Text("Manage wallpapers"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const MediaManagerScreen()));
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
                  await ButtonLayoutService.saveCarryOverSettings({
                    'button_layout': carryOverLayout,
                    'wallpaper': carryOverWallpaper,
                    'ringtone': carryOverRingtone,
                    'volume': carryOverVolume,
                  });
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
        setState(() => _serverStatus = "ERROR: ${e.toString()}");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Pocket Provisioner $_appVersion"),
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

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  Device? _target;
  bool _isProcessing = false;
  int _pendingCount = 0;
  bool _carryOverLayout = false;

  @override
  void initState() {
    super.initState();
    _loadNextTarget();
    _loadCarryOverSettings();
  }

  Future<void> _loadCarryOverSettings() async {
    final settings = await ButtonLayoutService.getCarryOverSettings();
    if (mounted) setState(() => _carryOverLayout = settings['button_layout'] ?? false);
  }

  Future<void> _loadNextTarget() async {
    final next = await DatabaseHelper.instance.getNextPendingDevice();
    final count = await DatabaseHelper.instance.getPendingCount();
    setState(() {
      _target = next;
      _isProcessing = false;
      _pendingCount = count;
    });
  }

  /// Shows a streamlined dialog to customise per-handset button labels when
  /// the button layout is being carried over.
  Future<void> _showCustomiseLabelsDialog(String mac, String model) async {
    final layout = await ButtonLayoutService.getLayoutForModel(model);
    final activeKeys = layout.where((k) => k.type != 'none' && k.value.isNotEmpty).toList();
    if (activeKeys.isEmpty) return;

    // Load any existing overrides for this MAC
    final existingOverrides = await ButtonLayoutService.getLabelOverrides(mac);
    final Map<int, TextEditingController> controllers = {
      for (final k in activeKeys)
        k.id: TextEditingController(
          text: existingOverrides[k.id.toString()] ?? k.label,
        ),
    };

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Customise Labels"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "The button layout is being carried over. "
                "Edit any labels for this handset, or tap Skip to keep defaults.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ...activeKeys.map((k) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: controllers[k.id],
                      decoration: InputDecoration(
                        labelText: "Key ${k.id} — ${k.type.toUpperCase()} ${k.value}",
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Skip (use defaults)"),
          ),
          ElevatedButton(
            onPressed: () async {
              final overrides = <String, String>{
                for (final k in activeKeys)
                  k.id.toString(): controllers[k.id]!.text.trim(),
              };
              await ButtonLayoutService.saveLabelOverrides(mac, overrides);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Save Labels"),
          ),
        ],
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _showConfirmationDialog(String cleanMac) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Assignment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Matched MAC: $cleanMac\nto Extension: ${_target!.extension} (${_target!.label})",
            ),
            if (_carryOverLayout) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.content_copy, size: 14, color: Colors.orange),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        "Button layout carry-over is ON — you'll be able to customise labels after confirming.",
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isProcessing = false);
            },
            child: const Text("Rescan / Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              try {
                await DatabaseHelper.instance.assignMac(_target!.id!, cleanMac);
                if (mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("SUCCESS — $cleanMac assigned!"),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
                // Show label customisation if carry-over layout is active
                if (_carryOverLayout && mounted) {
                  await _showCustomiseLabelsDialog(cleanMac, _target!.model);
                }
                _loadNextTarget();
              } catch (e) {
                if (mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Error saving assignment: $e"),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  setState(() => _isProcessing = false);
                }
              }
            },
            child: const Text("Confirm & Next"),
          ),
        ],
      ),
    );
    // Safety net: ensure scanner is re-enabled if dialog closed unexpectedly
    if (mounted) setState(() => _isProcessing = false);
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
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "📋 Pending: $_pendingCount devices remaining",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (_carryOverLayout)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.content_copy, size: 14, color: Colors.deepOrange),
                  SizedBox(width: 6),
                  Text(
                    "Button layout carry-over is ON",
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Colors.blueAccent,
            child: Column(
              children: [
                const Text("SCANNING FOR:", style: TextStyle(color: Colors.white70, letterSpacing: 1.5)),
                const SizedBox(height: 5),
                Text(
                  _target!.label, 
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
                final String cleanMac = rawMac.replaceAll(':', '').toUpperCase();
                if (mounted) await _showConfirmationDialog(cleanMac);
              },
            ),
          ),
        ],
      ),
    );
  }
}
