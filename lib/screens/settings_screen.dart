import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/button_layout_service.dart';
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
  final TextEditingController _portController =
      TextEditingController();
  final TextEditingController _targetUrlController =
      TextEditingController();

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
      _portController.text = prefs.getString('server_port') ?? '8080';
      _targetUrlController.text =
          prefs.getString('target_provisioning_url') ?? '';
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
    await prefs.setString(
        'server_port', _portController.text.trim());
    await prefs.setString('target_provisioning_url',
        _targetUrlController.text.trim());
    await ButtonLayoutService.saveCarryOverSettings({
      'button_layout': _carryOverLayout,
      'wallpaper': _carryOverWallpaper,
      'ringtone': _carryOverRingtone,
      'volume': _carryOverVolume,
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _targetUrlController.dispose();
    super.dispose();
  }

  void _showDmsHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What is DMS / EPM?'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Endpoint Manager (EPM)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'A tool for configuration, firmware updates, and deployment. '
                  'Used in VoIP environments (e.g., FreePBX Endpoint Manager) to manage desk phones.'),
              SizedBox(height: 10),
              Text('DMS (Device Management System)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Similar to EPM, used by carriers for initial device provisioning.'),
              SizedBox(height: 10),
              Divider(),
              Text(
                'The "Target Server" tells the phone where to go after Pocket Provisioner '
                'applies the initial config.',
                style: TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Global Settings'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                await _saveSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings Saved')));
                  Navigator.pop(context);
                }
              },
            )
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Server'),
              Tab(text: 'Management'),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            children: [
              // ── Tab 1: Server ──────────────────────────────────────────
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Provisioning Server Port',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                      'Port the HTTP provisioning server listens on.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  TextField(
                    controller: _portController,
                    decoration:
                        const InputDecoration(hintText: '8080'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text('Target DMS / EPM Server',
                          style: TextStyle(
                              fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.help_outline,
                            size: 18, color: Colors.grey),
                        onPressed: _showDmsHelp,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const Text(
                      'URL where the phone calls home after initial provisioning.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey)),
                  TextField(
                    controller: _targetUrlController,
                    decoration: const InputDecoration(
                      hintText:
                          'https://your-pbx.example.com/provision',
                    ),
                  ),
                  const Divider(height: 32),
                  const Text('Carry-Over Settings (Scanner Mode)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                    'Apply these settings to all handsets when scanning MACs. '
                    'Per-device settings (SIP, VLAN, etc.) are configured via '
                    'the extension menu on the Review Import screen.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Button Layout'),
                    subtitle: const Text(
                        'Reuse model default layout for every handset'),
                    value: _carryOverLayout,
                    onChanged: (v) =>
                        setState(() => _carryOverLayout = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Wallpaper'),
                    subtitle:
                        const Text('Apply same wallpaper to all'),
                    value: _carryOverWallpaper,
                    onChanged: (v) =>
                        setState(() => _carryOverWallpaper = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Ringtone'),
                    subtitle: const Text(
                        'Apply same ringtone to all'),
                    value: _carryOverRingtone,
                    onChanged: (v) =>
                        setState(() => _carryOverRingtone = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Volume'),
                    subtitle: const Text(
                        'Apply same volume settings to all'),
                    value: _carryOverVolume,
                    onChanged: (v) =>
                        setState(() => _carryOverVolume = v),
                  ),
                ],
              ),

              // ── Tab 2: Management ──────────────────────────────────────
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    title: const Text('Manage Templates'),
                    subtitle: const Text(
                        'Edit Yealink / Cisco / Polycom Mustache templates'),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) =>
                                const TemplateManagerScreen())),
                  ),
                  ListTile(
                    title: const Text('Default Button Layouts'),
                    subtitle: const Text(
                        'Set model-level default button layouts (per-extension can override)'),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) =>
                                const ButtonLayoutEditorScreen())),
                  ),
                  ListTile(
                    title: const Text('Hosted Files'),
                    subtitle: const Text(
                        'View, edit and clone generated config files'),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) =>
                                const HostedFilesScreen())),
                  ),
                  ListTile(
                    title: const Text('Media Manager'),
                    subtitle: const Text(
                        'Manage wallpapers (rename / delete)'),
                    trailing:
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) =>
                                const MediaManagerScreen())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}