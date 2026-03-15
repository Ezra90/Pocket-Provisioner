import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../services/app_directories.dart';
import '../services/build_info.dart';
import '../services/mustache_renderer.dart';
import '../services/mustache_template_service.dart';
import '../services/provisioning_server.dart';
import '../services/button_layout_service.dart';
import '../services/phonebook_service.dart';
import '../services/update_service.dart';
import '../services/global_settings.dart';
import '../models/access_log_entry.dart';
import '../models/button_key.dart';
import '../models/device.dart';
import 'access_log_screen.dart';
import 'global_settings_screen.dart';
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
  String _appVersion = "Build 1";

  // Global provisioning mode (loaded from SharedPreferences)
  String _globalMode = GlobalSettings.modeDms;

  // Detected local IP — updated on init and on network changes
  String? _localIp;

  // Update state
  UpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;

  // Toast notification settings (loaded from SharedPreferences)
  bool _toastNotificationsEnabled = true;
  StreamSubscription<AccessLogEntry>? _logSubscription;
  // Track MACs that have already triggered a toast in this session
  final Set<String> _notifiedMacs = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadAppVersion();
    _autoCheckForUpdate();
    _loadGlobalMode();
    _detectLocalIp();
    _loadToastSettings();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }

  /// Loads toast notification preference from SharedPreferences.
  Future<void> _loadToastSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _toastNotificationsEnabled = prefs.getBool('toast_notifications') ?? true;
      });
    }
  }

  /// Toggles toast notifications and persists the setting.
  Future<void> _toggleToastNotifications(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('toast_notifications', enabled);
    if (mounted) {
      setState(() => _toastNotificationsEnabled = enabled);
    }
  }

  /// Subscribes to access log stream to show toast notifications when a device
  /// connects and accesses any file for the first time in this session.
  void _startLogListener() {
    _logSubscription?.cancel();
    _notifiedMacs.clear();
    _logSubscription = ProvisioningServer.accessLogStream.listen((entry) {
      if (!_toastNotificationsEnabled) return;
      
      // Create a unique key combining MAC (or IP fallback) and resource type
      // This allows one toast per resource type per device per session
      final deviceIdentifier = entry.resolvedMac ?? entry.clientIp;
      final notifyKey = '$deviceIdentifier:${entry.resourceType}';
      
      // Only notify once per device per resource type per session
      if (_notifiedMacs.contains(notifyKey)) return;
      _notifiedMacs.add(notifyKey);

      // Show toast notification with device info and what was accessed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 ${entry.toastSummary}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View Logs',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccessLogScreen()),
              ),
            ),
          ),
        );
      }
    });
  }

  /// Stops listening to log events (when server stops).
  void _stopLogListener() {
    _logSubscription?.cancel();
    _logSubscription = null;
  }

  /// Returns a user-friendly description of the current network status.
  String get _networkStatusText {
    if (_localIp == null) return 'No network detected';
    if (_isServerRunning) return 'Server: http://$_localIp:8080';
    return 'Network IP: $_localIp (ready to start)';
  }

  /// Detects the local IP address for display purposes without starting the
  /// server.  Tries WiFi IP first via [NetworkInfo], then falls back to
  /// enumerating network interfaces, prioritising physical adapters (wlan/eth/en)
  /// over virtual or VPN interfaces.
  Future<void> _detectLocalIp() async {
    try {
      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      if (ip == null) {
        final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4);
        final sorted = interfaces.toList()
          ..sort((a, b) {
            final aName = a.name.toLowerCase();
            final bName = b.name.toLowerCase();
            final aPhy = aName.startsWith('wlan') ||
                aName.startsWith('eth') ||
                aName.startsWith('en');
            final bPhy = bName.startsWith('wlan') ||
                bName.startsWith('eth') ||
                bName.startsWith('en');
            if (aPhy && !bPhy) return -1;
            if (!aPhy && bPhy) return 1;
            return aName.compareTo(bName);
          });
        for (final iface in sorted) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              ip = addr.address;
              break;
            }
          }
          if (ip != null) break;
        }
      }
      if (mounted && ip != null) setState(() => _localIp = ip);
    } catch (_) {
      // Non-fatal: IP detection failure should not break the UI
    }
  }

  Future<void> _loadGlobalMode() async {
    final mode = await GlobalSettings.getMode();
    if (mounted) setState(() => _globalMode = mode);
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      // Show build number and commit hash for CI builds, just build number for local
      final commitSuffix = BuildInfo.isCiBuild ? ' (${BuildInfo.commitSha})' : '';
      setState(() => _appVersion = "Build ${info.buildNumber}$commitSuffix");
    }
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
    
    // Get detailed status for better user feedback
    final status = await UpdateService.getUpdateStatus();
    final update = status.updateAvailable ? await UpdateService.checkForUpdate() : null;
    
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      _pendingUpdate = update;
    });
    
    if (update == null) {
      // Show detailed status message instead of generic "latest version"
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status.message)),
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
    // Request storage permission so the self-contained Pocket-Provisioner/
    // folder can be created at the root of external storage.
    await AppDirectories.ensureStoragePermission();

    final statuses = await [
      Permission.camera,
      Permission.location, // Critical for getting Local IP on Android
      // Android 13+ (API 33+): allows WiFi IP lookup without location permission
      Permission.nearbyWifiDevices,
    ].request();
    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera and location permissions are required for full functionality.")),
      );
    }
  }

  // --- IMPORT FORMAT HELP ---
  void _showImportFormatHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import File Format'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The app reads the first row as column headers (case-insensitive). '
                'Supported column names for each field:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildFormatRow(
                field: 'Extension *',
                headers: '"Extension", "Device Username", "Username", "User"',
              ),
              _buildFormatRow(
                field: 'Secret / Password',
                headers: '"Secret", "SIP Password", "DMS Password", or any column containing "pass"',
              ),
              _buildFormatRow(
                field: 'Label / Name',
                headers: '"Name", "Label", "Description", "Display Name", "Device Name", "Caller ID Name"',
              ),
              _buildFormatRow(
                field: 'Model',
                headers: '"Model", "Device Type", "Phone Model", "Handset"',
              ),
              _buildFormatRow(
                field: 'Phone / DID',
                headers: '"Phone", "Phone Number", "User ID", "DN", "DID", "Direct Dial", "Direct Number"',
              ),
              _buildFormatRow(
                field: 'MAC Address',
                headers: 'Any column containing "mac"',
              ),
              const SizedBox(height: 12),
              const Text(
                '* Extension column is required. All other columns are optional — '
                'the app will use sensible defaults when they are missing.\n\n'
                'If a Phone / DID value is found, it is prepended to the label '
                '(e.g. "0755551234 - Reception").',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatRow({required String field, required String headers}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(headers,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _dhcpRow(String dhcpOption, String description, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dhcpOption,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(description,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
          SelectableText(value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.blue)),
        ],
      ),
    );
  }

  /// Compact DHCP option row for inline display in server status card.
  Widget _dhcpOptionRow(String option, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(option,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blue),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $value'), duration: const Duration(seconds: 1)),
              );
            },
            child: const Icon(Icons.copy, size: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// Shows detailed DHCP configuration guide dialog.
  void _showDhcpGuide(BuildContext context) {
    final ip = _isServerRunning
        ? ProvisioningServer.serverUrl ?? _localIp ?? '<your-ip>'
        : 'http://${_localIp ?? '<your-ip>'}:8080';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("DHCP Configuration Guide"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Configure your router\'s DHCP options so handsets '
                'automatically find this provisioning server on boot:\n',
                style: TextStyle(fontSize: 13),
              ),
              _dhcpRow('Option 66 (Standard)',
                  'Primary provisioning server URL — used by Yealink, Polycom, Cisco, and most other VoIP phones',
                  ip),
              _dhcpRow('Option 160',
                  'Alternative provisioning URL — used by some vendors when Option 66 is reserved for TFTP',
                  ip),
              const SizedBox(height: 12),
              const Text(
                'Vendor Requirements:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Text(
                '• Yealink: Option 66 (HTTP/HTTPS) or Option 43 (vendor-specific)\n'
                '• Polycom VVX/Edge: Option 66 (HTTP) or provisioning via ZTP\n'
                '• Cisco MPP: Option 66 (HTTP)\n'
                '• Grandstream: Option 66 (HTTP/HTTPS)\n',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tips:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Text(
                '• Factory reset handsets so they query DHCP on boot.\n'
                '• Ensure firewall allows HTTP traffic on port 8080.\n'
                '• In DMS / Carrier mode, the handset contacts the DMS first, '
                'which then redirects to this server.\n'
                '• Some routers require Option 66 as plain IP without http:// prefix.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Got it"))
        ],
      ),
    );
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
          h == 'username' ||
          h == 'ext');
      int passIndex = headers.indexWhere((h) =>
          h.contains('dms password') ||
          h.contains('sip password') ||
          h.contains('secret') ||
          h == 'password' ||
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
          h == 'phone' ||
          h == 'dn' ||
          h.contains('user id') ||
          h.contains('phone number') ||
          h.contains('did') ||
          h.contains('direct dial') ||
          h.contains('direct number') ||
          h.contains('direct inward'));
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

      final outputDir = await AppDirectories.configsDir();

      // Load global settings once for the whole batch
      final gs = await GlobalSettings.load();

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
          if (deviceWallpaper.startsWith('LOCAL:')) {
            // LOCAL: prefix means server-hosted file - only resolve when server URL is available
            if (serverUrl != null) {
              final filename = deviceWallpaper.substring('LOCAL:'.length);
              deviceWallpaperUrl = '$serverUrl/media/$filename';
            }
            // If serverUrl is null, leave deviceWallpaperUrl empty (don't pass raw LOCAL: prefix)
          } else {
            // External URL - use as-is
            deviceWallpaperUrl = deviceWallpaper;
          }
        }

        // Resolve per-device ringtone to server URL
        String deviceRingtoneUrl = '';
        final deviceRingtone = ds?.ringtone;
        if (deviceRingtone != null && deviceRingtone.isNotEmpty) {
          final serverUrl = ProvisioningServer.serverUrl;
          if (deviceRingtone.startsWith('LOCAL:')) {
            // LOCAL: prefix means server-hosted file - only resolve when server URL is available
            if (serverUrl != null) {
              final filename = deviceRingtone.substring('LOCAL:'.length);
              deviceRingtoneUrl = '$serverUrl/ringtones/$filename';
            }
            // If serverUrl is null, leave deviceRingtoneUrl empty (don't pass raw LOCAL: prefix)
          } else {
            // External URL - use as-is
            deviceRingtoneUrl = deviceRingtone;
          }
        }

        // Resolve per-device firmware URL
        String deviceFirmwareUrl = '';
        final rawFirmwareUrl = ds?.firmwareUrl;
        if (rawFirmwareUrl != null && rawFirmwareUrl.isNotEmpty) {
          final serverUrl = ProvisioningServer.serverUrl;
          if (rawFirmwareUrl.startsWith('LOCAL:')) {
            // LOCAL: prefix means server-hosted file - only resolve when server URL is available
            if (serverUrl != null) {
              final filename = rawFirmwareUrl.substring('LOCAL:'.length);
              deviceFirmwareUrl = '$serverUrl/firmware/$filename';
            }
            // If serverUrl is null, leave deviceFirmwareUrl empty (don't pass raw LOCAL: prefix)
          } else {
            // External URL - use as-is
            deviceFirmwareUrl = rawFirmwareUrl;
          }
        }

        // Generate phonebook XML and resolve URL.
        // Only included when the provisioning server is running so the config
        // contains a reachable URL that phones can fetch at boot time.
        String? devicePhonebookUrl;
        final phonebookEntries = ds?.phonebookEntries;
        final activeServerUrl = ProvisioningServer.serverUrl;
        if (phonebookEntries != null &&
            phonebookEntries.isNotEmpty &&
            activeServerUrl != null) {
          final pbFilename = await PhonebookService.saveForExtension(
            device.extension,
            phonebookEntries,
            displayName: device.label,
            model: device.model,
          );
          if (pbFilename != null) {
            devicePhonebookUrl = '$activeServerUrl/phonebook/$pbFilename';
          }
        }

        // Apply line-level overrides from device settings
        final effectiveExtension = ds?.extensionOverride ?? device.extension;
        final effectivePassword = ds?.passwordOverride ?? device.secret;
        final effectiveDisplayName = ds?.displayNameOverride ?? device.label;
        final effectiveAuthUsername = ds?.authUsernameOverride ?? effectiveExtension;

        final variables = MustacheRenderer.buildVariables(
          macAddress: device.macAddress!,
          extension: effectiveExtension,
          displayName: effectiveDisplayName,
          secret: effectivePassword,
          authUsername: effectiveAuthUsername,
          model: device.model,
          sipServer: gs.resolveSipServer(ds?.sipServer),
          provisioningUrl: gs.resolveProvisioningUrl(
              ds?.provisioningUrl, serverUrl: ProvisioningServer.serverUrl),
          sipPort: ds?.sipPort ?? (gs.isDmsMode ? null : gs.sipPort),
          transport: ds?.transport ?? (gs.isDmsMode ? null : gs.transport),
          regExpiry: ds?.regExpiry,
          outboundProxyHost: ds?.outboundProxyHost,
          outboundProxyPort: ds?.outboundProxyPort,
          backupServer: ds?.backupServer,
          backupPort: ds?.backupPort,
          voiceVlanId: ds?.voiceVlanId ?? gs.voiceVlanId,
          dataVlanId: ds?.dataVlanId,
          wallpaperUrl: deviceWallpaperUrl,
          ringtoneUrl: deviceRingtoneUrl,
          ntpServer: ds?.ntpServer ?? gs.ntpServer,
          timezone: ds?.timezone ?? gs.timezone,
          adminPassword: ds?.adminPassword ?? gs.adminPassword,
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
          phonebookUrl: devicePhonebookUrl,
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
      _stopLogListener();
      setState(() {
        _serverStatus = "OFFLINE";
        _isServerRunning = false;
        _statusColor = Colors.red.shade100;
      });
      WakelockPlus.disable();
      _detectLocalIp(); // Refresh local IP after stopping
    } else {
      try {
        String url = await ProvisioningServer.instance.start(8080);
        _startLogListener();
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pocket-Provisioner',
                style: TextStyle(fontSize: 18)),
            Text(
              _appVersion,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.monitor_heart),
            tooltip: 'App Logs',
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
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Global Settings',
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (c) => const GlobalSettingsScreen()),
              );
              if (changed == true) _loadGlobalMode();
            },
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
                      ? 'Update available: ${_pendingUpdate!.version}'
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
        child: ListView(
        padding: const EdgeInsets.all(16.0),
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
                          'Update available: ${_pendingUpdate!.version} — Tap to install',
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
                    const SizedBox(height: 8),
                    // Always show network info (even when offline)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi, size: 14, color: _localIp != null ? Colors.green : Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            _networkStatusText,
                            style: TextStyle(
                              fontSize: 12,
                              color: _localIp != null ? Colors.black54 : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _detectLocalIp,
                            child: const Icon(Icons.refresh, size: 14, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                    // DHCP options section - expanded inline
                    if (_localIp != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.settings_ethernet, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 6),
                                const Text(
                                  'DHCP Options',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: () => _showDhcpGuide(context),
                                  child: const Icon(Icons.help_outline, size: 16, color: Colors.blue),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _dhcpOptionRow('Option 66', 
                                _isServerRunning 
                                    ? ProvisioningServer.serverUrl ?? 'http://$_localIp:8080'
                                    : 'http://$_localIp:8080'),
                            _dhcpOptionRow('Option 160', 
                                _isServerRunning 
                                    ? ProvisioningServer.serverUrl ?? 'http://$_localIp:8080'
                                    : 'http://$_localIp:8080'),
                          ],
                        ),
                      ),
                    ] else ...[
                      // DHCP options guidance — when no IP
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Flexible(
                              child: Text(
                                "Connect to WiFi to see DHCP options",
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _showDhcpGuide(context),
                              child: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.blueGrey),
                  tooltip: 'View expected column headers',
                  onPressed: _showImportFormatHelp,
                ),
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

            const SizedBox(height: 20),

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
          Text('${widget.info.version} is available.',
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
