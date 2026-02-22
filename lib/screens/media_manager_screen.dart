import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/wallpaper_service.dart';
import '../services/provisioning_server.dart';
import '../data/device_templates.dart';

class MediaManagerScreen extends StatefulWidget {
  const MediaManagerScreen({super.key});

  @override
  State<MediaManagerScreen> createState() => _MediaManagerScreenState();
}

class _MediaManagerScreenState extends State<MediaManagerScreen> {
  List<WallpaperInfo> _wallpapers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWallpapers();
  }

  Future<void> _loadWallpapers() async {
    setState(() => _loading = true);
    final list = await WallpaperService.listWallpapers();
    if (mounted) {
      setState(() {
        _wallpapers = list;
        _loading = false;
      });
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    _showSnack('URL copied to clipboard');
  }

  Future<void> _importWallpaper() async {
    final nameController = TextEditingController();
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final spec = DeviceTemplates.getSpecForModel(selectedModel);
          return AlertDialog(
            title: const Text('Import Wallpaper'),
            content: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Name (required)',
                    hintText: 'e.g. LobbyT54W',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Target Model / Resolution',
                    border: OutlineInputBorder(),
                  ),
                  items: DeviceTemplates.wallpaperSpecs.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedModel = v!),
                ),
                const SizedBox(height: 8),
                Text(
                  'Required: ${spec.width}×${spec.height} ${spec.format.toUpperCase()}',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Pick Image'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final customName = nameController.text.trim();
    if (customName.isEmpty) {
      _showSnack('A custom name is required');
      return;
    }

    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null) return;

    try {
      final spec = DeviceTemplates.getSpecForModel(selectedModel);
      await WallpaperService.processAndSaveWallpaper(
          result.files.single.path!, spec, customName);
      _showSnack('Wallpaper "$customName" imported');
      _loadWallpapers();
    } catch (e) {
      _showSnack('Import failed: $e');
    }
  }

  Future<void> _showWallpaperActions(WallpaperInfo info) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star, color: Colors.green),
              title: const Text('Set as Active'),
              subtitle: const Text('Use this wallpaper for config generation'),
              onTap: () => Navigator.pop(ctx, 'set_active'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Re-process'),
              subtitle: const Text('Re-resize from original with different spec'),
              onTap: () => Navigator.pop(ctx, 'reprocess'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    switch (action) {
      case 'set_active':
        await _setActive(info);
      case 'rename':
        await _renameWallpaper(info);
      case 'reprocess':
        await _reprocessWallpaper(info);
      case 'delete':
        await _deleteWallpaper(info);
    }
  }

  Future<void> _setActive(WallpaperInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('public_wallpaper_url', 'LOCAL:${info.filename}');
    _showSnack('"${info.name}" set as active wallpaper');
  }

  Future<void> _renameWallpaper(WallpaperInfo info) async {
    final controller = TextEditingController(text: info.name);
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;

    // Try to infer spec from filename dimensions
    final dimMatch = WallpaperService.dimensionPattern.firstMatch(info.filename);
    if (dimMatch != null) {
      final w = int.tryParse(dimMatch.group(1)!);
      final h = int.tryParse(dimMatch.group(2)!);
      for (final entry in DeviceTemplates.wallpaperSpecs.entries) {
        if (entry.value.width == w && entry.value.height == h) {
          selectedModel = entry.key;
          break;
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Wallpaper'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rename')),
        ],
      ),
    );

    if (confirmed != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == info.name) return;

    try {
      final spec = DeviceTemplates.getSpecForModel(selectedModel);
      await WallpaperService.renameWallpaper(info.filename, newName, spec);
      _showSnack('Renamed to "$newName"');
      _loadWallpapers();
    } catch (e) {
      _showSnack('Rename failed: $e');
    }
  }

  Future<void> _reprocessWallpaper(WallpaperInfo info) async {
    if (info.originalPath == null) {
      _showSnack('No original file found for "${info.name}"');
      return;
    }

    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final spec = DeviceTemplates.getSpecForModel(selectedModel);
          return AlertDialog(
            title: const Text('Re-process Wallpaper'),
            content: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'New Target Model / Resolution',
                    border: OutlineInputBorder(),
                  ),
                  items: DeviceTemplates.wallpaperSpecs.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedModel = v!),
                ),
                const SizedBox(height: 8),
                Text(
                  'Will resize to: ${spec.width}×${spec.height}',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Re-process')),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    try {
      final spec = DeviceTemplates.getSpecForModel(selectedModel);
      await WallpaperService.reprocessFromOriginal(info.name, spec);
      _showSnack('"${info.name}" re-processed');
      _loadWallpapers();
    } catch (e) {
      _showSnack('Re-process failed: $e');
    }
  }

  Future<void> _deleteWallpaper(WallpaperInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Wallpaper'),
        content: Text(
            'Delete "${info.name}"? This will remove both the resized and original files.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await WallpaperService.deleteWallpaper(info.filename);
      _showSnack('"${info.name}" deleted');
      _loadWallpapers();
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ProvisioningServer.serverUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            tooltip: 'Import wallpaper',
            onPressed: _importWallpaper,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadWallpapers,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadWallpapers,
              child: _wallpapers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_not_supported,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No wallpapers yet',
                              style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _importWallpaper,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('Import Wallpaper'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _wallpapers.length,
                      itemBuilder: (context, index) {
                        final info = _wallpapers[index];
                        final dimMatch =
                            WallpaperService.dimensionPattern.firstMatch(info.filename);
                        final dims = dimMatch != null
                            ? '${dimMatch.group(1)}×${dimMatch.group(2)}'
                            : '';
                        final mediaUrl = serverUrl != null
                            ? '$serverUrl/media/${info.filename}'
                            : null;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Image.file(
                                  File(info.resizedPath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image,
                                      size: 40,
                                      color: Colors.grey),
                                ),
                              ),
                            ),
                            title: Text(info.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (dims.isNotEmpty)
                                  Text(dims,
                                      style: const TextStyle(fontSize: 12)),
                                Text(_formatBytes(info.fileSize),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                                if (mediaUrl != null)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          mediaUrl,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.blueGrey),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 16),
                                        tooltip: 'Copy URL',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _copyUrl(mediaUrl),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            trailing: const Icon(Icons.more_vert),
                            onTap: () => _showWallpaperActions(info),
                          ),
                        );
                      },
                    ),
            ),
        ),
    );
  }
}
