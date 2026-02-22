import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/provisioning_server.dart';
import 'access_log_screen.dart';
import 'file_editor_screen.dart';

class HostedFilesScreen extends StatefulWidget {
  const HostedFilesScreen({super.key});

  @override
  State<HostedFilesScreen> createState() => _HostedFilesScreenState();
}

class _HostedFilesScreenState extends State<HostedFilesScreen> {
  List<_ConfigEntry> _generatedConfigs = [];
  List<FileSystemEntity> _customTemplates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final appDir = await getApplicationDocumentsDirectory();

    final configDir =
        Directory(p.join(appDir.path, 'generated_configs'));
    final templateDir =
        Directory(p.join(appDir.path, 'custom_templates'));

    // Load configs with metadata, sorted newest first
    final configEntries = <_ConfigEntry>[];
    if (await configDir.exists()) {
      for (final f
          in configDir.listSync().whereType<File>()) {
        final stat = await f.stat();
        configEntries.add(
            _ConfigEntry(file: f, stat: stat));
      }
      configEntries.sort(
          (a, b) => b.stat.modified.compareTo(a.stat.modified));
    }

    final templates = (await templateDir.exists())
        ? templateDir.listSync().whereType<File>().toList()
        : <FileSystemEntity>[];

    if (mounted) {
      setState(() {
        _generatedConfigs = configEntries;
        _customTemplates = templates;
        _loading = false;
      });
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL copied to clipboard')),
      );
    }
  }

  Future<void> _deleteConfig(_ConfigEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Config'),
        content: Text(
            'Delete ${p.basename(entry.file.path)}?\n\nThis file will no longer be served.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await entry.file.delete();
      _loadFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteAllConfigs() async {
    if (_generatedConfigs.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Configs'),
        content: Text(
            'Delete all ${_generatedConfigs.length} generated config files? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final entry in _generatedConfigs) {
      try {
        await entry.file.delete();
      } catch (_) {}
    }
    _loadFiles();
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    return '${(bytes / 1024).toStringAsFixed(1)}kB';
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ProvisioningServer.serverUrl;
    final displayUrl =
        serverUrl != null ? '$serverUrl/' : 'Server not running';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosted Files'),
        actions: [
          if (serverUrl != null)
            IconButton(
              icon: const Icon(Icons.monitor_heart),
              tooltip: 'Access Log',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (c) => const AccessLogScreen()),
              ),
            ),
          if (_generatedConfigs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep,
                  color: Colors.red),
              tooltip: 'Delete all configs',
              onPressed: _deleteAllConfigs,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadFiles,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFiles,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // Server URL banner
                  Card(
                    color: serverUrl != null
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.router,
                              color: serverUrl != null
                                  ? Colors.green
                                  : Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(displayUrl,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                          if (serverUrl != null)
                            IconButton(
                              icon: const Icon(Icons.copy,
                                  size: 18),
                              tooltip: 'Copy URL',
                              onPressed: () =>
                                  _copyUrl(displayUrl),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Persistence note
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.blueGrey),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Config files persist here until you manually delete '
                            'them. Tap a file to edit it, or use "Clone for New '
                            'Extension" (📋) to reuse a config as a template.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Generated Configs
                  Row(
                    children: [
                      const Text('Generated Configs',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(width: 6),
                      Text('(${_generatedConfigs.length})',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_generatedConfigs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No generated configs yet',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._generatedConfigs.map((entry) {
                      final name =
                          p.basename(entry.file.path);
                      final subtitle =
                          '${_formatSize(entry.stat.size)}  •  '
                          '${_formatDate(entry.stat.modified)}';
                      return Dismissible(
                        key: ValueKey(entry.file.path),
                        direction:
                            DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(
                              right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete,
                              color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete?'),
                              content: Text('Delete $name?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(
                                            ctx, false),
                                    child: const Text(
                                        'Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton
                                      .styleFrom(
                                          backgroundColor:
                                              Colors.red),
                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, true),
                                  child: const Text(
                                      'Delete'),
                                ),
                              ],
                            ),
                          ) ??
                              false;
                        },
                        onDismissed: (_) async {
                          try {
                            await entry.file.delete();
                          } catch (_) {}
                          _loadFiles();
                        },
                        child: ListTile(
                          dense: true,
                          leading: const Icon(
                              Icons.description,
                              color: Colors.blue),
                          title: Text(name),
                          subtitle: Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Copy URL
                              if (serverUrl != null)
                                IconButton(
                                  icon: const Icon(
                                      Icons.link,
                                      size: 18),
                                  tooltip: 'Copy URL',
                                  onPressed: () =>
                                      _copyUrl(
                                          '$serverUrl/$name'),
                                ),
                              // Delete
                              IconButton(
                                icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red),
                                tooltip: 'Delete',
                                onPressed: () =>
                                    _deleteConfig(entry),
                              ),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) =>
                                    FileEditorScreen(
                                  filePath:
                                      entry.file.path,
                                  fileName: name,
                                ),
                              ),
                            );
                            _loadFiles();
                          },
                        ),
                      );
                    }),

                  const Divider(height: 28),

                  // Custom Templates
                  const Text('Custom Templates',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 6),
                  if (_customTemplates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No custom templates found',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._customTemplates.map((f) {
                      final name = p.basename(f.path);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.edit_document,
                            color: Colors.orange),
                        title: Text(name),
                        trailing: const Icon(
                            Icons.lock_outline,
                            size: 16),
                        onTap: () {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Use the Template Manager to edit templates.'),
                            ),
                          );
                        },
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

/// Pairs a [File] with its [FileStat] so sorting by date is cheap.
class _ConfigEntry {
  final File file;
  final FileStat stat;
  const _ConfigEntry({required this.file, required this.stat});
}

