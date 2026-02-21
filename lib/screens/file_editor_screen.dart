import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../services/provisioning_server.dart';

class FileEditorScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const FileEditorScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late TextEditingController _controller;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final content = await File(widget.filePath).readAsString();
      if (mounted) {
        setState(() {
          _controller.text = content;
          _loading = false;
        });
        _controller.addListener(() {
          if (!_dirty) setState(() => _dirty = true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error reading file: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _save() async {
    try {
      await File(widget.filePath).writeAsString(_controller.text);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('File saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete ${widget.fileName}?'),
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
      await File(widget.filePath).delete();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('File deleted')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error deleting: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Clone for new extension ───────────────────────────────────────────────

  /// Extracts common provisioning fields from the config content.
  _ParsedFields _parseFields(String content) {
    String ext = '';
    String secret = '';
    String label = '';
    final mac =
        p.basenameWithoutExtension(widget.fileName).toUpperCase();

    // Yealink .cfg
    ext = RegExp(r'account\.1\.user_name\s*=\s*(.+)')
            .firstMatch(content)
            ?.group(1)
            ?.trim() ??
        '';
    if (ext.isEmpty) {
      // Cisco XML
      ext = RegExp(r'<UserID>(.*?)</UserID>')
              .firstMatch(content)
              ?.group(1)
              ?.trim() ??
          '';
    }
    if (ext.isEmpty) {
      // Polycom XML
      ext = RegExp(r'auth_user="([^"]+)"')
              .firstMatch(content)
              ?.group(1)
              ?.trim() ??
          '';
    }

    // Secret
    secret = RegExp(r'account\.1\.password\s*=\s*(.+)')
                .firstMatch(content)
                ?.group(1)
                ?.trim() ??
        '';
    if (secret.isEmpty) {
      secret = RegExp(r'<AuthPassword>(.*?)</AuthPassword>')
                  .firstMatch(content)
                  ?.group(1)
                  ?.trim() ??
          '';
    }
    if (secret.isEmpty) {
      secret = RegExp(r'password="([^"]+)"')
                  .firstMatch(content)
                  ?.group(1)
                  ?.trim() ??
          '';
    }

    // Label / display name
    label = RegExp(r'account\.1\.label\s*=\s*(.+)')
                .firstMatch(content)
                ?.group(1)
                ?.trim() ??
        '';
    if (label.isEmpty) {
      label = RegExp(r'<Name>(.*?)</Name>')
                  .firstMatch(content)
                  ?.group(1)
                  ?.trim() ??
          '';
    }
    if (label.isEmpty) {
      label =
          RegExp(r'reg\.1\.label="([^"]+)"').firstMatch(content)?.group(1)?.trim() ??
              '';
    }

    return _ParsedFields(
        ext: ext, secret: secret, label: label, mac: mac);
  }

  /// Applies targeted substitutions for all supported config formats.
  String _applySubstitutions(
    String content, {
    required String oldExt,
    required String newExt,
    required String oldSecret,
    required String newSecret,
    required String oldLabel,
    required String newLabel,
    required String oldMac,
    required String newMac,
  }) {
    var r = content;
    final isXml = widget.fileName.toLowerCase().endsWith('.xml');

    if (newExt.isNotEmpty && oldExt.isNotEmpty && oldExt != newExt) {
      if (isXml) {
        r = r
            .replaceAll('<UserID>$oldExt</UserID>',
                '<UserID>$newExt</UserID>')
            .replaceAll('<AuthID>$oldExt</AuthID>',
                '<AuthID>$newExt</AuthID>')
            .replaceAll('auth_user="$oldExt"',
                'auth_user="$newExt"')
            .replaceAll('"$oldExt"', '"$newExt"');
      } else {
        // Yealink .cfg — only replace in account.X.* lines
        r = r.replaceAllMapped(
          RegExp(
              r'(account\.\d+\.(?:user_name|auth_name|user_id|registrar_uri)\s*=\s*)' +
                  RegExp.escape(oldExt),
              multiLine: true),
          (m) => '${m.group(1)}$newExt',
        );
      }
    }

    if (newSecret.isNotEmpty &&
        oldSecret.isNotEmpty &&
        oldSecret != newSecret) {
      if (isXml) {
        r = r
            .replaceAll(
                '<AuthPassword>$oldSecret</AuthPassword>',
                '<AuthPassword>$newSecret</AuthPassword>')
            .replaceAll(
                'password="$oldSecret"', 'password="$newSecret"');
      } else {
        r = r.replaceAllMapped(
          RegExp(
              r'(account\.\d+\.password\s*=\s*)' +
                  RegExp.escape(oldSecret),
              multiLine: true),
          (m) => '${m.group(1)}$newSecret',
        );
      }
    }

    if (newLabel.isNotEmpty &&
        oldLabel.isNotEmpty &&
        oldLabel != newLabel) {
      if (isXml) {
        r = r
            .replaceAll('<Name>$oldLabel</Name>',
                '<Name>$newLabel</Name>')
            .replaceAll(
                '<DisplayName>$oldLabel</DisplayName>',
                '<DisplayName>$newLabel</DisplayName>')
            .replaceAll(
                'reg.1.label="$oldLabel"', 'reg.1.label="$newLabel"');
      } else {
        r = r.replaceAllMapped(
          RegExp(
              r'(account\.\d+\.label\s*=\s*)' +
                  RegExp.escape(oldLabel),
              multiLine: true),
          (m) => '${m.group(1)}$newLabel',
        );
        r = r.replaceAllMapped(
          RegExp(
              r'((?:features\.display_name|local_label)\s*=\s*)' +
                  RegExp.escape(oldLabel),
              multiLine: true),
          (m) => '${m.group(1)}$newLabel',
        );
      }
    }

    // MAC replacement (both plain and colon-formatted)
    if (oldMac.isNotEmpty && newMac.isNotEmpty && oldMac != newMac) {
      r = r.replaceAll(oldMac, newMac);
      final oldFmt = _fmt(oldMac);
      final newFmt = _fmt(newMac);
      if (oldFmt != oldMac) r = r.replaceAll(oldFmt, newFmt);
    }

    return r;
  }

  static String _fmt(String mac) {
    final c = mac.replaceAll(':', '').toUpperCase();
    if (c.length == 12) {
      return '${c.substring(0, 2)}:${c.substring(2, 4)}:'
          '${c.substring(4, 6)}:${c.substring(6, 8)}:'
          '${c.substring(8, 10)}:${c.substring(10, 12)}';
    }
    return mac;
  }

  Future<void> _cloneConfig() async {
    final fields = _parseFields(_controller.text);
    final ext = p.extension(widget.fileName); // .cfg or .xml

    final macCtrl = TextEditingController();
    final extCtrl = TextEditingController(text: fields.ext);
    final secretCtrl = TextEditingController(text: fields.secret);
    final labelCtrl = TextEditingController(text: fields.label);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clone Config — New Extension'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Creates a copy of this config with the new '
                'MAC as the filename and updated credentials.',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: macCtrl,
                decoration: const InputDecoration(
                  labelText: 'New MAC (new filename)',
                  hintText: 'AABBCCDDEEFF',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: extCtrl,
                decoration: const InputDecoration(
                  labelText: 'Extension / Username',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secretCtrl,
                decoration: const InputDecoration(
                  labelText: 'SIP Secret / Password',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display Name / Label',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
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
            child: const Text('Clone & Save'),
          ),
        ],
      ),
    );

    macCtrl.dispose();

    if (confirmed != true) return;

    final newMac = macCtrl.text
        .trim()
        .replaceAll(RegExp(r'[:\-\s]'), '')
        .toUpperCase();
    if (newMac.length < 12) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invalid MAC — enter at least 12 hex chars'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    final newFileName = '$newMac$ext';
    final newPath =
        p.join(p.dirname(widget.filePath), newFileName);

    // Warn if target already exists
    if (await File(newPath).exists() && mounted) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('File Exists'),
          content: Text('$newFileName already exists. Overwrite?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Overwrite')),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    final newContent = _applySubstitutions(
      _controller.text,
      oldExt: fields.ext,
      newExt: extCtrl.text.trim(),
      oldSecret: fields.secret,
      newSecret: secretCtrl.text.trim(),
      oldLabel: fields.label,
      newLabel: labelCtrl.text.trim(),
      oldMac: fields.mac,
      newMac: newMac,
    );

    extCtrl.dispose();
    secretCtrl.dispose();
    labelCtrl.dispose();

    try {
      await File(newPath).writeAsString(newContent);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved as $newFileName')));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FileEditorScreen(
              filePath: newPath, fileName: newFileName),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving clone: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('URL copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ProvisioningServer.serverUrl;
    final fileUrl = serverUrl != null
        ? '$serverUrl/${widget.fileName}'
        : 'Server not running';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: TextStyle(
              color: _dirty ? Colors.orange : null,
              fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_copy_outlined),
            tooltip: 'Clone for New Extension',
            onPressed: _loading ? null : _cloneConfig,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _loading ? null : _save,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'Delete',
            onPressed: _delete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // URL banner
                Card(
                  margin: const EdgeInsets.all(10),
                  color: serverUrl != null
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.link,
                            color: serverUrl != null
                                ? Colors.green
                                : Colors.orange,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(fileUrl,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ),
                        if (serverUrl != null)
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            tooltip: 'Copy URL',
                            onPressed: () => _copyUrl(fileUrl),
                          ),
                      ],
                    ),
                  ),
                ),

                // Persistence note
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  color: Colors.blue.shade50,
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.blueGrey),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'This file persists until you delete it. '
                          'Use the 📋 Clone button to create a copy for a new extension.',
                          style: TextStyle(
                              fontSize: 11, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),

                // Editor
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(10, 6, 10, 10),
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(10),
                      ),
                      textAlignVertical: TextAlignVertical.top,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Holds extracted provisioning credentials from a config file.
class _ParsedFields {
  final String ext;
  final String secret;
  final String label;
  final String mac;
  const _ParsedFields(
      {required this.ext,
      required this.secret,
      required this.label,
      required this.mac});
}

