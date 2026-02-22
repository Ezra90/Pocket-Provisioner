import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../data/device_templates.dart';
import '../services/provisioning_server.dart';
import '../services/ringtone_service.dart';
import '../services/wallpaper_service.dart';
import '../services/mustache_template_service.dart';
import 'access_log_screen.dart';
import 'button_layout_editor.dart';
import 'file_editor_screen.dart';

/// Unified file manager with tabs for all server-hosted content:
///   1. Configs   — generated MAC config files
///   2. Wallpapers — resized wallpaper images
///   3. Ringtones  — WAV ringtone files (max 1 MB)
///   4. Templates  — Mustache provisioning templates
///   5. Phonebook  — XML phonebook files (NEW)
class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('URL copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ProvisioningServer.serverUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Manager'),
        actions: [
          if (serverUrl != null)
            IconButton(
              icon: const Icon(Icons.monitor_heart),
              tooltip: 'Access Log',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AccessLogScreen())),
            ),
          // Button Layouts (model-level defaults) still accessible here
          IconButton(
            icon: const Icon(Icons.keyboard),
            tooltip: 'Default Button Layouts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ButtonLayoutEditorScreen()),
            ),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.description), text: 'Configs'),
            Tab(icon: Icon(Icons.image), text: 'Wallpapers'),
            Tab(icon: Icon(Icons.music_note), text: 'Ringtones'),
            Tab(icon: Icon(Icons.article), text: 'Templates'),
            Tab(icon: Icon(Icons.contacts), text: 'Phonebook'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: [
            _ConfigsTab(onCopy: _copyToClipboard),
            _WallpapersTab(onCopy: _copyToClipboard),
            _RingtonesTab(onCopy: _copyToClipboard),
            _TemplatesTab(onCopy: _copyToClipboard),
            _PhonebookTab(onCopy: _copyToClipboard),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Configs
// ─────────────────────────────────────────────────────────────────────────────

class _ConfigsTab extends StatefulWidget {
  final void Function(String) onCopy;
  const _ConfigsTab({required this.onCopy});

  @override
  State<_ConfigsTab> createState() => _ConfigsTabState();
}

class _ConfigsTabState extends State<_ConfigsTab>
    with AutomaticKeepAliveClientMixin {
  List<_FileEntry> _files = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'generated_configs'));
    final entries = <_FileEntry>[];
    if (await dir.exists()) {
      for (final f in dir.listSync().whereType<File>()) {
        final stat = await f.stat();
        entries.add(_FileEntry(file: f, stat: stat));
      }
      entries.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    }
    if (mounted) setState(() { _files = entries; _loading = false; });
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Configs?'),
        content: Text('Delete all ${_files.length} config files?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final e in _files) { try { await e.file.delete(); } catch (_) {} }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverUrl = ProvisioningServer.serverUrl;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _ServerBanner(serverUrl: serverUrl),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Generated Configs (${_files.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_files.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 16),
                        label: const Text('Delete All', style: TextStyle(color: Colors.red, fontSize: 12)),
                        onPressed: _deleteAll,
                      ),
                    IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
                  ],
                ),
                if (_files.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No configs generated yet', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._files.map((e) {
                    final name = p.basename(e.file.path);
                    return Dismissible(
                      key: ValueKey(e.file.path),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete?'),
                            content: Text('Delete $name?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ) ?? false;
                      },
                      onDismissed: (_) async {
                        try { await e.file.delete(); } catch (_) {}
                        _load();
                      },
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.description, color: Colors.blue),
                        title: Text(name),
                        subtitle: Text(
                          '${_fmtBytes(e.stat.size)}  •  ${_fmtDate(e.stat.modified)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: serverUrl != null
                            ? IconButton(
                                icon: const Icon(Icons.link, size: 18),
                                tooltip: 'Copy URL',
                                onPressed: () => widget.onCopy('$serverUrl/$name'),
                              )
                            : null,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FileEditorScreen(
                                filePath: e.file.path,
                                fileName: name,
                              ),
                            ),
                          );
                          _load();
                        },
                      ),
                    );
                  }),
              ],
            ),
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Wallpapers
// ─────────────────────────────────────────────────────────────────────────────

class _WallpapersTab extends StatefulWidget {
  final void Function(String) onCopy;
  const _WallpapersTab({required this.onCopy});

  @override
  State<_WallpapersTab> createState() => _WallpapersTabState();
}

class _WallpapersTabState extends State<_WallpapersTab>
    with AutomaticKeepAliveClientMixin {
  List<WallpaperInfo> _wallpapers = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await WallpaperService.listWallpapers();
    if (mounted) setState(() { _wallpapers = list; _loading = false; });
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _import() async {
    final nameCtrl = TextEditingController();
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) {
          final spec = DeviceTemplates.getSpecForModel(selectedModel);
          return AlertDialog(
            title: const Text('Import Wallpaper'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
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
                  onChanged: (v) => setDS(() => selectedModel = v!),
                ),
                const SizedBox(height: 8),
                Text('Required: ${spec.width}×${spec.height} ${spec.format.toUpperCase()}',
                    style: const TextStyle(fontSize: 12, color: Colors.blue)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pick Image')),
            ],
          );
        },
      ),
    );
    if (ok != true) { nameCtrl.dispose(); return; }

    final customName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (customName.isEmpty) { _snack('A name is required'); return; }

    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null) return;

    try {
      final spec = DeviceTemplates.getSpecForModel(selectedModel);
      await WallpaperService.processAndSaveWallpaper(result.files.single.path!, spec, customName);
      _snack('Wallpaper "$customName" imported');
      _load();
    } catch (e) {
      _snack('Import failed: $e');
    }
  }

  Future<void> _showActions(WallpaperInfo info) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.refresh), title: const Text('Re-process'), subtitle: const Text('Re-resize from original'), onTap: () => Navigator.pop(ctx, 'reprocess')),
          ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Delete', style: TextStyle(color: Colors.red)), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'rename': await _rename(info);
      case 'reprocess': await _reprocess(info);
      case 'delete': await _delete(info);
    }
  }

  Future<void> _rename(WallpaperInfo info) async {
    final ctrl = TextEditingController(text: info.name);
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;
    final dimMatch = WallpaperService.dimensionPattern.firstMatch(info.filename);
    if (dimMatch != null) {
      final w = int.tryParse(dimMatch.group(1)!);
      final h = int.tryParse(dimMatch.group(2)!);
      for (final e in DeviceTemplates.wallpaperSpecs.entries) {
        if (e.value.width == w && e.value.height == h) { selectedModel = e.key; break; }
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Wallpaper'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'New Name', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rename')),
        ],
      ),
    );
    if (ok != true) { ctrl.dispose(); return; }
    final newName = ctrl.text.trim();
    ctrl.dispose();
    if (newName.isEmpty || newName == info.name) return;
    try {
      final spec = DeviceTemplates.getSpecForModel(selectedModel);
      await WallpaperService.renameWallpaper(info.filename, newName, spec);
      _snack('Renamed to "$newName"');
      _load();
    } catch (e) { _snack('Rename failed: $e'); }
  }

  Future<void> _reprocess(WallpaperInfo info) async {
    if (info.originalPath == null) { _snack('No original found for "${info.name}"'); return; }
    String selectedModel = DeviceTemplates.wallpaperSpecs.keys.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) {
          final spec = DeviceTemplates.getSpecForModel(selectedModel);
          return AlertDialog(
            title: const Text('Re-process Wallpaper'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedModel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'New Target Model', border: OutlineInputBorder()),
                items: DeviceTemplates.wallpaperSpecs.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                onChanged: (v) => setDS(() => selectedModel = v!),
              ),
              const SizedBox(height: 8),
              Text('Will resize to: ${spec.width}×${spec.height}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Re-process')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      final spec = DeviceTemplates.getSpecForModel(selectedModel);
      await WallpaperService.reprocessFromOriginal(info.name, spec);
      _snack('"${info.name}" re-processed');
      _load();
    } catch (e) { _snack('Re-process failed: $e'); }
  }

  Future<void> _delete(WallpaperInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Wallpaper'),
        content: Text('Delete "${info.name}"? Removes both resized and original files.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try { await WallpaperService.deleteWallpaper(info.filename); _snack('"${info.name}" deleted'); _load(); }
    catch (e) { _snack('Delete failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverUrl = ProvisioningServer.serverUrl;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _wallpapers.isEmpty
                  ? ListView(children: [
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No wallpapers yet', style: TextStyle(color: Colors.grey))),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _wallpapers.length,
                      itemBuilder: (context, i) {
                        final info = _wallpapers[i];
                        final dimMatch = WallpaperService.dimensionPattern.firstMatch(info.filename);
                        final dims = dimMatch != null ? '${dimMatch.group(1)}×${dimMatch.group(2)}' : '';
                        final mediaUrl = serverUrl != null ? '$serverUrl/media/${info.filename}' : null;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: Image.file(
                                  File(info.resizedPath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey),
                                ),
                              ),
                            ),
                            title: Text(info.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (dims.isNotEmpty) Text(dims, style: const TextStyle(fontSize: 12)),
                                Text(_fmtBytes(info.fileSize), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                if (mediaUrl != null)
                                  InkWell(
                                    onTap: () => widget.onCopy(mediaUrl),
                                    child: Text(mediaUrl, style: const TextStyle(fontSize: 10, color: Colors.blueGrey), overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _showActions(info),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _import,
        tooltip: 'Import Wallpaper',
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 — Ringtones (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class _RingtonesTab extends StatefulWidget {
  final void Function(String) onCopy;
  const _RingtonesTab({required this.onCopy});

  @override
  State<_RingtonesTab> createState() => _RingtonesTabState();
}

class _RingtonesTabState extends State<_RingtonesTab>
    with AutomaticKeepAliveClientMixin {
  List<RingtoneInfo> _ringtones = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await RingtoneService.listRingtones();
    if (mounted) setState(() { _ringtones = list; _loading = false; });
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _upload() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Ringtone'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name (required)',
                hintText: 'e.g. MyRingtone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('WAV files only (max 1 MB).',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pick Audio')),
        ],
      ),
    );
    if (ok != true) { nameCtrl.dispose(); return; }

    final customName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (customName.isEmpty) { _snack('A name is required'); return; }

    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['wav']);
    if (result == null) return;

    try {
      await RingtoneService.convertAndSave(result.files.single.path!, customName);
      _snack('"$customName" uploaded');
      _load();
    } catch (e) {
      _snack('Upload failed: $e');
    }
  }

  Future<void> _rename(RingtoneInfo info) async {
    final ctrl = TextEditingController(text: info.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Ringtone'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'New Name', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rename')),
        ],
      ),
    );
    if (ok != true) { ctrl.dispose(); return; }
    final newName = ctrl.text.trim();
    ctrl.dispose();
    if (newName.isEmpty || newName == info.name) return;
    try {
      await RingtoneService.renameRingtone(info.filename, newName);
      _snack('Renamed to "$newName"');
      _load();
    } catch (e) { _snack('Rename failed: $e'); }
  }

  Future<void> _delete(RingtoneInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Ringtone'),
        content: Text('Delete "${info.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try { await RingtoneService.deleteRingtone(info.filename); _snack('"${info.name}" deleted'); _load(); }
    catch (e) { _snack('Delete failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverUrl = ProvisioningServer.serverUrl;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _ringtones.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(Icons.music_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('No ringtones yet', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _upload,
                              icon: const Icon(Icons.upload),
                              label: const Text('Upload Ringtone'),
                            ),
                          ],
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _ringtones.length,
                      itemBuilder: (context, i) {
                        final info = _ringtones[i];
                        final ringtoneUrl = serverUrl != null ? '$serverUrl/ringtones/${info.filename}' : null;
                        return Dismissible(
                          key: ValueKey(info.filename),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete?'),
                                content: Text('Delete "${info.name}"?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ) ?? false;
                          },
                          onDismissed: (_) async {
                            try { await RingtoneService.deleteRingtone(info.filename); } catch (_) {}
                            _load();
                          },
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              child: const Icon(Icons.music_note, color: Colors.purple),
                            ),
                            title: Text(info.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${_fmtBytes(info.sizeBytes)}  •  WAV',
                                    style: const TextStyle(fontSize: 11)),
                                if (ringtoneUrl != null)
                                  InkWell(
                                    onTap: () => widget.onCopy(ringtoneUrl),
                                    child: Text(ringtoneUrl,
                                        style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ringtoneUrl != null)
                                  IconButton(
                                    icon: const Icon(Icons.link, size: 18),
                                    tooltip: 'Copy URL',
                                    onPressed: () => widget.onCopy(ringtoneUrl),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                                  tooltip: 'Rename',
                                  onPressed: () => _rename(info),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _upload,
        tooltip: 'Upload Ringtone',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 4 — Templates
// ─────────────────────────────────────────────────────────────────────────────

class _TemplatesTab extends StatefulWidget {
  final void Function(String) onCopy;
  const _TemplatesTab({required this.onCopy});

  @override
  State<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<_TemplatesTab>
    with AutomaticKeepAliveClientMixin {
  int _version = 0;
  final _keyCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load(String key) async {
    try {
      final content = await MustacheTemplateService.instance.loadTemplate(key);
      setState(() { _keyCtrl.text = key; _contentCtrl.text = content; });
    } catch (e) { _snack('Could not load: $e'); }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final filename = result.files.single.name;
    setState(() {
      _contentCtrl.text = content;
      if (_keyCtrl.text.isEmpty) _keyCtrl.text = filename.split('.').first;
    });
    _snack('Imported $filename — edit key and tap Save');
  }

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    final content = _contentCtrl.text;
    if (key.isEmpty || content.isEmpty) { _snack('Key and content are required'); return; }
    await MustacheTemplateService.instance.saveCustomTemplate(key, content);
    setState(() => _version++);
    _snack('Saved "$key"');
  }

  Future<void> _export() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) { _snack('Enter a template key first'); return; }
    try {
      await MustacheTemplateService.instance.exportTemplate(key);
    } catch (e) { _snack('Export failed: $e'); }
  }

  Future<void> _deleteCustom(String key) async {
    await MustacheTemplateService.instance.deleteCustomTemplate(key);
    setState(() => _version++);
    _snack('Custom override for "$key" removed');
  }

  String _sourceLabel(TemplateSource s) => switch (s) {
    TemplateSource.bundled => 'Bundled default',
    TemplateSource.customOverride => 'Custom override',
    TemplateSource.customNew => 'Custom (new)',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverUrl = ProvisioningServer.serverUrl;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Template list
        FutureBuilder<List<TemplateInfo>>(
          key: ValueKey(_version),
          future: MustacheTemplateService.instance.listAll(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available Templates', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...snap.data!.map((t) {
                  final url = serverUrl != null ? '$serverUrl/templates/${t.key}.mustache' : null;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      t.source == TemplateSource.bundled ? Icons.article_outlined : Icons.edit_document,
                      size: 20,
                      color: t.source == TemplateSource.bundled ? Colors.grey : Colors.blue,
                    ),
                    title: Text(t.displayName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_sourceLabel(t.source), style: const TextStyle(fontSize: 11)),
                        if (url != null)
                          InkWell(
                            onTap: () => widget.onCopy(url),
                            child: Text(url, style: const TextStyle(fontSize: 10, color: Colors.blueGrey), overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    trailing: t.source != TemplateSource.bundled
                        ? IconButton(
                            icon: const Icon(Icons.restore, size: 18, color: Colors.red),
                            tooltip: 'Restore bundled default',
                            onPressed: () => _deleteCustom(t.key),
                          )
                        : null,
                    onTap: () => _load(t.key),
                  );
                }),
                const Divider(height: 20),
              ],
            );
          },
        ),
        // Editor area
        const Text('Template Editor', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _keyCtrl,
          decoration: const InputDecoration(
            labelText: 'Template Key',
            hintText: 'e.g. yealink_t4x',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _contentCtrl,
          maxLines: 12,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: 'Template Content (Mustache)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Import File'),
              onPressed: _import,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Save'),
              onPressed: _save,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Export'),
              onPressed: _export,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 5 — Phonebook (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class _PhonebookTab extends StatefulWidget {
  final void Function(String) onCopy;
  const _PhonebookTab({required this.onCopy});

  @override
  State<_PhonebookTab> createState() => _PhonebookTabState();
}

class _PhonebookTabState extends State<_PhonebookTab>
    with AutomaticKeepAliveClientMixin {
  List<_FileEntry> _files = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'phonebook'));
    final entries = <_FileEntry>[];
    if (await dir.exists()) {
      for (final f in dir.listSync().whereType<File>()) {
        final stat = await f.stat();
        entries.add(_FileEntry(file: f, stat: stat));
      }
      entries.sort((a, b) => a.file.path.compareTo(b.file.path));
    }
    if (mounted) setState(() { _files = entries; _loading = false; });
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml', 'txt'],
    );
    if (result == null) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'phonebook'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final dest = File(p.join(dir.path, result.files.single.name));
      await File(result.files.single.path!).copy(dest.path);
      _snack('Phonebook uploaded');
      _load();
    } catch (e) { _snack('Upload failed: $e'); }
  }

  Future<void> _delete(_FileEntry e) async {
    final name = p.basename(e.file.path);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Phonebook?'),
        content: Text('Delete $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try { await e.file.delete(); _snack('$name deleted'); _load(); }
    catch (err) { _snack('Delete failed: $err'); }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverUrl = ProvisioningServer.serverUrl;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _files.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            const Icon(Icons.contacts, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('No phonebook files yet', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _upload,
                              icon: const Icon(Icons.upload),
                              label: const Text('Upload Phonebook XML'),
                            ),
                          ],
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _files.length,
                      itemBuilder: (context, i) {
                        final e = _files[i];
                        final name = p.basename(e.file.path);
                        final pbUrl = serverUrl != null ? '$serverUrl/phonebook/$name' : null;
                        return ListTile(
                          leading: const Icon(Icons.contacts, color: Colors.teal),
                          title: Text(name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fmtBytes(e.stat.size), style: const TextStyle(fontSize: 11)),
                              if (pbUrl != null)
                                InkWell(
                                  onTap: () => widget.onCopy(pbUrl),
                                  child: Text(pbUrl, style: const TextStyle(fontSize: 10, color: Colors.blueGrey), overflow: TextOverflow.ellipsis),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pbUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.link, size: 18),
                                  tooltip: 'Copy URL',
                                  onPressed: () => widget.onCopy(pbUrl),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                tooltip: 'Delete',
                                onPressed: () => _delete(e),
                              ),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FileEditorScreen(
                                  filePath: e.file.path,
                                  fileName: name,
                                ),
                              ),
                            );
                            _load();
                          },
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _upload,
        tooltip: 'Upload Phonebook',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ServerBanner extends StatelessWidget {
  final String? serverUrl;
  const _ServerBanner({required this.serverUrl});

  @override
  Widget build(BuildContext context) {
    final running = serverUrl != null;
    return Card(
      color: running ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.router, color: running ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                running ? '$serverUrl/' : 'Server not running',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileEntry {
  final File file;
  final FileStat stat;
  const _FileEntry({required this.file, required this.stat});
}

/// Formats [bytes] into a human-readable size string.
String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

String _fmtDate(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}
