import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../services/app_directories.dart';
import '../services/mustache_renderer.dart';
import '../services/mustache_template_service.dart';
import '../services/provisioning_server.dart';
import '../services/button_layout_service.dart';
import '../services/update_service.dart';
import '../models/button_key.dart';
import '../models/device.dart';
import 'access_log_screen.dart';
import 'model_assignment_screen.dart';
import 'extensions_screen.dart';
import 'file_manager_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _serverStatus = "OFFLINE";
  bool _isServerRunning = false;
  Color _statusColor = Colors.red.shade100;
  String _appVersion = "v0.0.4";

  // Update state
  UpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadAppVersion();
    _autoCheckForUpdate();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = "v${info.version}");
  }

  Future<void> _autoCheckForUpdate() async {
    final update = await UpdateService.checkForUpdate();
    if (mounted && update != null) {
      setState(() => _pendingUpdate = update);
    }
  }

  Future<void> _manualCheckForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _pendingUpdate = null;
    });
    final update = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      _pendingUpdate = update;
    });
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    } else {
      _showUpdateDialog(update);
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(info: info),
    ).then((_) {
      if (mounted) setState(() => _pendingUpdate = null);
    });
  }

  Future<void> _checkPermissions() async {
    // Request storage permission so the self-contained Pocket Provisioner/
    // folder can be created at the root of external storage.
    await AppDirectories.ensureStoragePermission();

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

  // --- SMART CSV / EXCEL IMPORT ---
  Future<void> _importFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx'],
    );

    if (result == null) return;

    try {
      final File file = File(result.files.single.path!);
      final String fileName = result.files.single.name.toLowerCase();

      List<List<dynamic>> rows;

      if (fileName.endsWith('.xlsx')) {
        // ── Excel (.xlsx) parsing ──────────────────────────────────────────
        final bytes = await file.readAsBytes();
        final excel = xl.Excel.decodeBytes(bytes);
        final sheetName = excel.tables.keys.first;
        final sheet = excel.tables[sheetName];
        if (sheet == null || sheet.rows.isEmpty) throw "Empty Excel file";

        rows = sheet.rows.map((row) {
          return row.map((cell) {
            if (cell == null) return '';
            final v = cell.value;
            if (v == null) return '';
            if (v is xl.TextCellValue) return v.value;
            if (v is xl.IntCellValue) return v.value.toString();
            if (v is xl.DoubleCellValue) {
              final d = v.value;
              // Format whole-number doubles as integers (e.g. 101.0 → "101")
              return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
            }
            if (v is xl.BoolCellValue) return v.value.toString();
            return v.toString();
          }).toList();
        }).toList();
      } else {
        // ── CSV / TXT parsing ─────────────────────────────────────────────
        final String rawContent = await file.readAsString();
        rows = const CsvToListConverter().convert(rawContent, eol: "\n");
      }

      if (rows.isEmpty) throw "Empty file";

      List<dynamic> headers = rows[0].map((e) => e.toString().toLowerCase().trim()).toList();
      
      // Smart Header Matching — supports Telstra qsetup, Carrier/Broadworks,
      // FreePBX, and generic CSV/Excel exports.
      int extIndex = headers.indexWhere((h) =>
          h.contains('device username') ||
          h.contains('extension') ||
          h == 'user' ||
          h == 'username');
      int passIndex = headers.indexWhere((h) =>
          h.contains('dms password') ||
          h.contains('secret') ||
          h.contains('pass'));
      int nameIndex = headers.indexWhere((h) =>
          h == 'name' ||
          h.contains('device name') ||
          h.contains('label') ||
          h.contains('description') ||
          h.contains('display name') ||
          h.contains('caller id name'));
      int modelIndex = headers.indexWhere((h) =>
          h.contains('device type') ||
          h.contains('model') ||
          h.contains('phone model') ||
          h.contains('handset'));
      int phoneIndex = headers.indexWhere((h) =>
          h.contains('user id') ||
          h.contains('phone') ||
          h == 'dn' ||
          h.contains('did') ||
          h.contains('direct'));
      int macIndex = headers.indexWhere((h) => h.contains('mac'));

      if (extIndex == -1) throw "Could not find an Extension / Device Username column. Expected a column named 'Extension', 'Device Username', 'Username', or 'User'.";

      final prefs = await SharedPreferences.getInstance();
      final lastModel = prefs.getString('last_used_model');
      final String defaultModel =
          (lastModel != null && DeviceTemplates.supportedModels.contains(lastModel))
              ? lastModel
              : DeviceTemplates.supportedModels.first;

      final List<Device> parsedDevices = [];
      for (int i = 1; i < rows.length; i++) {
        var row = rows[i];
        if (row.length <= extIndex) continue;

        String extension = row[extIndex].toString().trim();
        if (extension.isEmpty) continue;
        String secret = (passIndex != -1 && row.length > passIndex) ? row[passIndex].toString().trim() : "1234";
        
        // Use CSV/Excel model if available and recognised, otherwise fall back to default
        String rawModel = (modelIndex != -1 && row.length > modelIndex) ? row[modelIndex].toString().trim() : '';
        String model = DeviceTemplates.supportedModels.contains(rawModel) ? rawModel : defaultModel;
        
        String baseName = (nameIndex != -1 && row.length > nameIndex) ? row[nameIndex].toString().trim() : extension;
        String phoneNumber = (phoneIndex != -1 && row.length > phoneIndex) ? row[phoneIndex].toString().trim() : "";
        String finalLabel = phoneNumber.isNotEmpty ? "$phoneNumber - $baseName" : baseName;

        String? mac = (macIndex != -1 && row.length > macIndex) ? row[macIndex].toString() : null;
        if (mac != null) {
          mac = mac.replaceAll(':', '').toUpperCase();
          if (mac.length < 10) mac = null; 
        }

        parsedDevices.add(Device(
          model: model,
          extension: extension,
          secret: secret,
          label: finalLabel,
          macAddress: mac,
          status: mac != null ? 'READY' : 'PENDING',
        ));
      }

      if (parsedDevices.isEmpty) throw "No valid rows found in the file";

      if (!mounted) return;
      final imported = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (c) => ModelAssignmentScreen(
            devices: parsedDevices,
            defaultModel: defaultModel,
          ),
        ),
      );

      if (imported != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imported $imported devices!"))
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

      int generated = 0;

      for (final device in devices) {
        if (device.macAddress == null || device.macAddress!.isEmpty) continue;

        final ds = device.deviceSettings;

        // Resolve button layout: per-device only
        List<ButtonKey>? lineKeys;
        if (ds?.buttonLayout != null &&
            ds!.buttonLayout!.any((k) => k.type != 'none')) {
          lineKeys = ds.buttonLayout!.map((k) => k.clone()).toList();
          final overrides =
              await ButtonLayoutService.getLabelOverrides(device.macAddress!);
          for (final key in lineKeys) {
            final override = overrides[key.id.toString()];
            if (override != null) key.label = override;
          }
        }

        final templateKey = await MustacheRenderer.resolveTemplateKey(device.model);

        // Resolve per-device wallpaper to server URL.
        // Note: if the provisioning server is not running when configs are
        // generated, ProvisioningServer.serverUrl is null and LOCAL: wallpaper
        // URLs will be omitted from static config files.
        String deviceWallpaperUrl = '';
        final deviceWallpaper = device.wallpaper;
        if (deviceWallpaper != null && deviceWallpaper.isNotEmpty) {
          final serverUrl = ProvisioningServer.serverUrl;
          if (deviceWallpaper.startsWith('LOCAL:') && serverUrl != null) {
            final filename = deviceWallpaper.substring('LOCAL:'.length);
            deviceWallpaperUrl = '$serverUrl/media/$filename';
          } else {
            deviceWallpaperUrl = deviceWallpaper;
          }
        }

        // Resolve per-device ringtone to server URL
        String deviceRingtoneUrl = '';
        final deviceRingtone = ds?.ringtone;
        if (deviceRingtone != null && deviceRingtone.isNotEmpty) {
          final serverUrl = ProvisioningServer.serverUrl;
          if (deviceRingtone.startsWith('LOCAL:') && serverUrl != null) {
            final filename = deviceRingtone.substring('LOCAL:'.length);
            deviceRingtoneUrl = '$serverUrl/ringtones/$filename';
          } else {
            deviceRingtoneUrl = deviceRingtone;
          }
        }

        // Resolve per-device firmware URL
        String deviceFirmwareUrl = '';
        final rawFirmwareUrl = ds?.firmwareUrl;
        if (rawFirmwareUrl != null && rawFirmwareUrl.isNotEmpty) {
          final serverUrl = ProvisioningServer.serverUrl;
          if (rawFirmwareUrl.startsWith('LOCAL:') && serverUrl != null) {
            final filename = rawFirmwareUrl.substring('LOCAL:'.length);
            deviceFirmwareUrl = '$serverUrl/firmware/$filename';
          } else {
            deviceFirmwareUrl = rawFirmwareUrl;
          }
        }

        final variables = MustacheRenderer.buildVariables(
          macAddress: device.macAddress!,
          extension: device.extension,
          displayName: device.label,
          secret: device.secret,
          model: device.model,
          // All per-device settings; empty string = not configured
          sipServer: ds?.sipServer ?? '',
          provisioningUrl: ds?.provisioningUrl ?? '',
          sipPort: ds?.sipPort,
          transport: ds?.transport,
          regExpiry: ds?.regExpiry,
          outboundProxyHost: ds?.outboundProxyHost,
          outboundProxyPort: ds?.outboundProxyPort,
          backupServer: ds?.backupServer,
          backupPort: ds?.backupPort,
          voiceVlanId: ds?.voiceVlanId,
          dataVlanId: ds?.dataVlanId,
          wallpaperUrl: deviceWallpaperUrl,
          ringtoneUrl: deviceRingtoneUrl,
          ntpServer: ds?.ntpServer,
          timezone: ds?.timezone,
          adminPassword: ds?.adminPassword,
          voicemailNumber: ds?.voicemailNumber,
          screensaverTimeout: ds?.screensaverTimeout,
          webUiEnabled: ds?.webUiEnabled,
          cdpLldpEnabled: ds?.cdpLldpEnabled,
          autoAnswer: ds?.autoAnswer,
          autoAnswerMode: ds?.autoAnswerMode,
          dndDefault: ds?.dndDefault,
          callWaiting: ds?.callWaiting,
          cfwAlways: ds?.cfwAlways,
          cfwBusy: ds?.cfwBusy,
          cfwNoAnswer: ds?.cfwNoAnswer,
          syslogServer: ds?.syslogServer,
          dialPlan: ds?.dialPlan,
          dstEnable: ds?.dstEnable,
          debugLevel: ds?.debugLevel,
          firmwareUrl: deviceFirmwareUrl.isNotEmpty ? deviceFirmwareUrl : null,
          lineKeys: lineKeys,
        );
        final rendered = await MustacheRenderer.render(templateKey, variables);
        final contentType =
            MustacheTemplateService.contentTypes[templateKey] ?? 'text/plain';
        final ext = contentType == 'application/xml' ? 'xml' : 'cfg';
        final mac = device.macAddress!.replaceAll(':', '').toUpperCase();
        final file = File(p.join(outputDir.path, '$mac.$ext'));
        await file.writeAsString(rendered);
        generated++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Generated configs for $generated devices!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error generating configs: $e"),
              backgroundColor: Colors.red),
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
        String url = await ProvisioningServer.instance.start(8080);
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
          if (_isServerRunning)
            IconButton(
              icon: const Icon(Icons.monitor_heart),
              tooltip: 'Access Log',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const AccessLogScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'File Manager',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (c) => const FileManagerScreen())),
          ),
          // Update indicator: spinning while checking, badge when update ready.
          if (_checkingUpdate)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.system_update),
                  tooltip: _pendingUpdate != null
                      ? 'Update available: v${_pendingUpdate!.version}'
                      : 'Check for Updates',
                  onPressed: _pendingUpdate != null
                      ? () => _showUpdateDialog(_pendingUpdate!)
                      : _manualCheckForUpdate,
                ),
                if (_pendingUpdate != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Update available banner
            if (_pendingUpdate != null)
              GestureDetector(
                onTap: () => _showUpdateDialog(_pendingUpdate!),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.new_releases, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Update available: v${_pendingUpdate!.version} — Tap to install',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

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
                    onPressed: _importFile,
                    icon: const Icon(Icons.file_upload),
                    label: const Text("Import CSV / Excel"),
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
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const ExtensionsScreen()));
                },
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone_android, size: 40, color: Colors.white),
                    SizedBox(height: 8),
                    Text("EXTENSIONS", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("Manage & Configure Handsets", style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Update dialog ─────────────────────────────────────────────────────────────

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    await UpdateService.downloadAndInstall(
      widget.info,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onError: (msg) {
        if (mounted) setState(() { _error = msg; _downloading = false; });
      },
    );

    // If no error, the installer launched — close the dialog.
    if (mounted && _error == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.system_update, color: Colors.orange),
          SizedBox(width: 8),
          Text('Update Available'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${widget.info.version} is available.',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (widget.info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.info.releaseNotes,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 6),
            Text(
              _progress > 0
                  ? 'Downloading… ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Starting download…',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        ElevatedButton.icon(
          onPressed: _downloading ? null : _startDownload,
          icon: const Icon(Icons.download),
          label: const Text('Download & Install'),
        ),
      ],
    );
  }
}
