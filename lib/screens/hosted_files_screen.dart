import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/provisioning_server.dart';
import 'file_editor_screen.dart';

class HostedFilesScreen extends StatefulWidget {
  const HostedFilesScreen({super.key});

  @override
  State<HostedFilesScreen> createState() => _HostedFilesScreenState();
}

class _HostedFilesScreenState extends State<HostedFilesScreen> {
  List<FileSystemEntity> _generatedConfigs = [];
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

    final configDir = Directory(p.join(appDir.path, 'generated_configs'));
    final templateDir = Directory(p.join(appDir.path, 'custom_templates'));

    final configs = (await configDir.exists())
        ? configDir.listSync().whereType<File>().toList()
        : <FileSystemEntity>[];
    final templates = (await templateDir.exists())
        ? templateDir.listSync().whereType<File>().toList()
        : <FileSystemEntity>[];

    if (mounted) {
      setState(() {
        _generatedConfigs = configs;
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

  @override
  Widget build(BuildContext context) {
    final serverUrl = ProvisioningServer.serverUrl;
    final displayUrl = serverUrl != null ? '$serverUrl/' : 'Server not running';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosted Files'),
        actions: [
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
                padding: const EdgeInsets.all(16),
                children: [
                  // --- Server URL Banner ---
                  Card(
                    color: serverUrl != null
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.router,
                            color: serverUrl != null
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              displayUrl,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          if (serverUrl != null)
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: 'Copy URL',
                              onPressed: () => _copyUrl(displayUrl),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- Generated Configs Section ---
                  const Text(
                    'Generated Configs',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (_generatedConfigs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No generated configs found',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._generatedConfigs.map((f) {
                      final name = p.basename(f.path);
                      return ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.description, color: Colors.blue),
                        title: Text(name),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => FileEditorScreen(
                                filePath: f.path,
                                fileName: name,
                              ),
                            ),
                          );
                          _loadFiles();
                        },
                      );
                    }),

                  const Divider(height: 32),

                  // --- Custom Templates Section ---
                  const Text(
                    'Custom Templates',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
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
                        trailing: const Icon(Icons.lock_outline, size: 16),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Templates are read-only here. Use the Template Manager to edit them.'),
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
