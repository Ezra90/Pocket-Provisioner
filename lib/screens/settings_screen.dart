import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../services/button_layout_service.dart';
import '../services/wallpaper_service.dart';
import '../data/device_templates.dart';
import 'template_manager.dart';
import 'button_layout_editor.dart';
import 'hosted_files_screen.dart';
import 'media_manager_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _sipServerController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _voiceVlanController = TextEditingController();
  final TextEditingController _ntpServerController = TextEditingController();
  final TextEditingController _timezoneController = TextEditingController();
  final TextEditingController _ringtoneController = TextEditingController();
  final TextEditingController _targetUrlController = TextEditingController();
  final TextEditingController _adminPasswordController = TextEditingController();
  final TextEditingController _wallpaperController = TextEditingController();

  String _refModel = DeviceTemplates.wallpaperSpecs.keys.first;

  // Carry-over settings
  bool _carryOverLayout = false;
  bool _carryOverWallpaper = false;
  bool _carryOverRingtone = false;
  bool _carryOverVolume = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sipServerController.text = prefs.getString('sip_server_address') ?? '';
      _portController.text = prefs.getString('server_port') ?? '8080';
      _voiceVlanController.text = prefs.getString('voice_vlan_id') ?? '';
      _ntpServerController.text = prefs.getString('ntp_server') ?? '';
      _timezoneController.text = prefs.getString('timezone_offset') ?? '';
      _ringtoneController.text = prefs.getString('default_ringtone') ?? '';
      _targetUrlController.text = prefs.getString('target_provisioning_url') ?? DeviceTemplates.defaultTarget;
      _adminPasswordController.text = prefs.getString('admin_password') ?? '';
      _wallpaperController.text = prefs.getString('public_wallpaper_url') ?? '';
    });

    final carryOver = await ButtonLayoutService.getCarryOverSettings();
    setState(() {
      _carryOverLayout = carryOver['button_layout'] ?? false;
      _carryOverWallpaper = carryOver['wallpaper'] ?? false;
      _carryOverRingtone = carryOver['ringtone'] ?? false;
      _carryOverVolume = carryOver['volume'] ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sip_server_address', _sipServerController.text.trim());
    await prefs.setString('server_port', _portController.text.trim());
    await prefs.setString('voice_vlan_id', _voiceVlanController.text.trim());
    await prefs.setString('ntp_server', _ntpServerController.text.trim());
    await prefs.setString('timezone_offset', _timezoneController.text.trim());
    await prefs.setString('default_ringtone', _ringtoneController.text.trim());
    await prefs.setString('target_provisioning_url', _targetUrlController.text.trim());
    await prefs.setString('admin_password', _adminPasswordController.text.trim());
    await prefs.setString('public_wallpaper_url', _wallpaperController.text.trim());

    await ButtonLayoutService.saveCarryOverSettings({
      'button_layout': _carryOverLayout,
      'wallpaper': _carryOverWallpaper,
      'ringtone': _carryOverRingtone,
      'volume': _carryOverVolume,
    });
  }

  @override
  void dispose() {
    _sipServerController.dispose();
    _portController.dispose();
    _voiceVlanController.dispose();
    _ntpServerController.dispose();
    _timezoneController.dispose();
    _ringtoneController.dispose();
    _targetUrlController.dispose();
    _adminPasswordController.dispose();
    _wallpaperController.dispose();
    super.dispose();
  }

  void _openWallpaperTools() {
    String selectedModel = _refModel;
    final nameController = TextEditingController();
    
    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
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
                  onChanged: (v) => setDialogState(() => selectedModel = v!),
                ),
                const SizedBox(height: 10),
                Text("Required: "+spec.width.toString()+"x"+spec.height.toString()+" "+spec.format.toUpperCase()),
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
                    
                    setState(() {
                      _wallpaperController.text = 'LOCAL:'+resizedFilename;
                    });
                    
                    if (mounted) {
                      Navigator.pop(ctx);
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

  void _showDmsHelp() {
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
              Text("The 'Target Server' setting tells the phone where to go after this app applies the initial wallpaper and buttons.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic))
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Got it"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Global Settings"),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                await _saveSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Settings Saved"))
                  );
                  Navigator.pop(context);
                }
              },
            )
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Network & SIP"),
              Tab(text: "Preferences"),
              Tab(text: "Management"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- TAB 1: NETWORK & SIP ---
            ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text("Primary SIP Server IP", style: TextStyle(fontWeight: FontWeight.bold)),
                const Text("Leave BLANK for DMS/Cloud. Enter IP for Local PBX.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                TextField(
                  controller: _sipServerController,
                  decoration: const InputDecoration(hintText: "e.g. 192.168.1.10"),
                ),
                const SizedBox(height: 20),
                const Text("Provisioning Server Port", style: TextStyle(fontWeight: FontWeight.bold)),
                const Text("Port the HTTP provisioning server listens on.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                TextField(
                  controller: _portController,
                  decoration: const InputDecoration(hintText: "8080"),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 20),
                const Text("Voice VLAN ID", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: _voiceVlanController,
                  decoration: const InputDecoration(hintText: "e.g. 100"),
                ),
              ],
            ),

            // --- TAB 2: PREFERENCES ---
            ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text("NTP Server", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: _ntpServerController,
                  decoration: const InputDecoration(hintText: "e.g. pool.ntp.org"),
                ),
                const SizedBox(height: 15),
                const Text("Timezone Offset", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: _timezoneController,
                  decoration: const InputDecoration(hintText: "e.g. +10"),
                ),
                const SizedBox(height: 15),
                const Text("Default Ringtone", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: _ringtoneController,
                  decoration: const InputDecoration(hintText: "e.g. Ring1.wav"),
                ),
                const SizedBox(height: 15),
                const Text("Wallpaper Source", style: TextStyle(fontWeight: FontWeight.bold)),
                const Text("Spec Reference:", style: TextStyle(fontSize: 11, color: Colors.grey)),
                DropdownButton<String>(
                  value: _refModel,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 12, color: Colors.black),
                  items: DeviceTemplates.wallpaperSpecs.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                  onChanged: (v) => setState(() => _refModel = v!),
                ),
                Text("Required: "+DeviceTemplates.getSpecForModel(_refModel).width.toString()+"x"+DeviceTemplates.getSpecForModel(_refModel).height.toString()+" "+DeviceTemplates.getSpecForModel(_refModel).format.toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.blue)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wallpaperController,
                        decoration: const InputDecoration(hintText: "URL or LOCAL_HOSTED"),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high, color: Colors.blue),
                      onPressed: _openWallpaperTools,
                    )
                  ],
                ),
                
                const Divider(height: 24),
                const Text("Carry-Over Settings", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  value: _carryOverLayout,
                  onChanged: (v) => setState(() => _carryOverLayout = v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text("Wallpaper"),
                  subtitle: const Text("Apply the same wallpaper to every handset"),
                  value: _carryOverWallpaper,
                  onChanged: (v) => setState(() => _carryOverWallpaper = v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text("Ringtone"),
                  subtitle: const Text("Apply the same ringtone to every handset"),
                  value: _carryOverRingtone,
                  onChanged: (v) => setState(() => _carryOverRingtone = v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text("Volume"),
                  subtitle: const Text("Apply the same volume settings to every handset"),
                  value: _carryOverVolume,
                  onChanged: (v) => setState(() => _carryOverVolume = v),
                ),
              ],
            ),

            // --- TAB 3: MANAGEMENT ---
            ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Row(
                  children: [
                    const Text("Target DMS / EPM Server", style: TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.help_outline, size: 18, color: Colors.grey),
                      onPressed: _showDmsHelp,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const Text("URL where phone goes NEXT.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                TextField(
                  controller: _targetUrlController,
                  decoration: const InputDecoration(
                    hintText: "https://your-pbx.example.com/provision",
                    helperText: "e.g. Carrier DMS or EPM URL",
                    helperStyle: TextStyle(fontSize: 10, color: Colors.grey)
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Local Admin Password", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: _adminPasswordController,
                  decoration: const InputDecoration(hintText: "e.g. admin"),
                  obscureText: true,
                ),
                
                const Divider(height: 24),
                ListTile(
                  title: const Text("Manage Templates"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const TemplateManagerScreen()));
                  },
                ),
                ListTile(
                  title: const Text("Button Layouts"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const ButtonLayoutEditorScreen()));
                  },
                ),
                ListTile(
                  title: const Text("Hosted Files"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const HostedFilesScreen()));
                  },
                ),
                ListTile(
                  title: const Text("Media Manager"),
                  subtitle: const Text("Manage wallpapers"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const MediaManagerScreen()));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}