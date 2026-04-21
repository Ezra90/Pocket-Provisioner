import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/phonebook_entry.dart';
import '../services/phonebook_service.dart';

/// Full-screen phonebook editor scoped to a single extension.
///
/// Allows the user to:
/// - View, add, edit and delete contacts.
/// - Auto-populate contacts from other extensions in the batch (name + ext).
/// - Import contacts from a simple CSV (Name,Phone) paste.
/// - Export the current list as a Yealink XML string.
///
/// Returns the edited [List<PhonebookEntry>] via [Navigator.pop].
class PerExtensionPhonebookEditorScreen extends StatefulWidget {
  final String extension;
  final String label;
  final String model;

  /// Existing phonebook entries to pre-populate.
  final List<PhonebookEntry>? initialEntries;

  /// Other extensions in the batch — used for auto-populate.
  final List<({String extension, String label})> batchExtensions;

  const PerExtensionPhonebookEditorScreen({
    super.key,
    required this.extension,
    required this.label,
    required this.model,
    this.initialEntries,
    this.batchExtensions = const [],
  });

  @override
  State<PerExtensionPhonebookEditorScreen> createState() =>
      _PerExtensionPhonebookEditorScreenState();
}

class _PerExtensionPhonebookEditorScreenState
    extends State<PerExtensionPhonebookEditorScreen> {
  late List<PhonebookEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.initialEntries?.map((e) => e.clone()).toList() ?? [];
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  /// Adds all batch extensions as contacts (skipping duplicates by phone).
  void _autoPopulateFromBatch() {
    if (widget.batchExtensions.isEmpty) {
      _snack('No other extensions in this import batch');
      return;
    }
    int added = 0;
    final existing = _entries.map((e) => e.phone).toSet();
    final sorted = List.of(widget.batchExtensions)
      ..sort((a, b) {
        final aNum = int.tryParse(a.extension) ?? 0;
        final bNum = int.tryParse(b.extension) ?? 0;
        return aNum.compareTo(bNum);
      });
    for (final ext in sorted) {
      if (!existing.contains(ext.extension)) {
        _entries.add(PhonebookEntry(
          name: ext.label.isNotEmpty ? ext.label : 'Ext ${ext.extension}',
          phone: ext.extension,
        ));
        added++;
      }
    }
    setState(() {});
    _snack('Added $added contact${added == 1 ? '' : 's'} from batch');
  }

  Future<void> _addOrEditEntry({PhonebookEntry? entry, int? index}) async {
    final result = await showDialog<PhonebookEntry>(
      context: context,
      builder: (_) => _ContactEditDialog(
        existing: entry,
        batchExtensions: widget.batchExtensions,
      ),
    );
    if (result == null) return;
    setState(() {
      if (index != null) {
        _entries[index] = result;
      } else {
        _entries.add(result);
      }
    });
  }

  Future<void> _deleteEntry(int index) async {
    final name = _entries[index].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => _entries.removeAt(index));
  }

  void _clearAll() {
    setState(() => _entries.clear());
  }

  /// Copies the Yealink XML for the current entries to the clipboard.
  void _copyXml() {
    final xml = PhonebookService.generateYealinkXml(
      _entries,
      displayName: widget.label,
    );
    Clipboard.setData(ClipboardData(text: xml));
    _snack('XML copied to clipboard');
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Phonebook', style: TextStyle(fontSize: 16)),
            Text(
              'Ext ${widget.extension}  —  ${widget.label}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Copy XML',
            onPressed: _entries.isEmpty ? null : _copyXml,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save phonebook',
            onPressed: () => Navigator.pop(context, _entries),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Action bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 15),
                    label: const Text('Auto-Fill from Batch',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _autoPopulateFromBatch,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Add Contact',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _addOrEditEntry(),
                  ),
                  if (_entries.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.clear_all, size: 15),
                      label: const Text('Clear All',
                          style: TextStyle(fontSize: 12)),
                      onPressed: _clearAll,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text(
                '${_entries.length} contact${_entries.length == 1 ? '' : 's'}  •  Tap to edit',
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const Divider(height: 1),
            // Contact list
            Expanded(
              child: _entries.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (_, i) {
                        final e = _entries[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.shade100,
                            child: Text(
                              e.name.isNotEmpty
                                  ? e.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(e.name),
                          subtitle: Text(e.phone,
                              style: const TextStyle(fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.group != 'All Contacts')
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 4),
                                  child: Chip(
                                    label: Text(e.group,
                                        style: const TextStyle(
                                            fontSize: 10)),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Delete',
                                onPressed: () => _deleteEntry(i),
                              ),
                            ],
                          ),
                          onTap: () =>
                              _addOrEditEntry(entry: e, index: i),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditEntry(),
        tooltip: 'Add contact',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.contacts, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No contacts yet',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Auto-Fill from Batch'),
            onPressed: _autoPopulateFromBatch,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Add Contact Manually'),
            onPressed: () => _addOrEditEntry(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact edit / add dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ContactEditDialog extends StatefulWidget {
  final PhonebookEntry? existing;
  final List<({String extension, String label})> batchExtensions;

  const _ContactEditDialog({
    required this.batchExtensions,
    this.existing,
  });

  @override
  State<_ContactEditDialog> createState() => _ContactEditDialogState();
}

class _ContactEditDialogState extends State<_ContactEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _groupCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.name ?? '');
    _phoneCtrl =
        TextEditingController(text: widget.existing?.phone ?? '');
    _groupCtrl = TextEditingController(
        text: widget.existing?.group ?? 'All Contacts');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  void _pickFromBatch() async {
    if (widget.batchExtensions.isEmpty) return;
    final sorted = List.of(widget.batchExtensions)
      ..sort((a, b) {
        final aNum = int.tryParse(a.extension) ?? 0;
        final bNum = int.tryParse(b.extension) ?? 0;
        return aNum.compareTo(bNum);
      });
    final picked = await showDialog<({String extension, String label})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick Extension'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final ext = sorted[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.phone, size: 16),
                title: Text(
                    ext.label.isNotEmpty ? ext.label : 'Ext ${ext.extension}',
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(ext.extension,
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(ctx, ext),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _phoneCtrl.text = picked.extension;
      if (_nameCtrl.text.isEmpty) {
        _nameCtrl.text =
            picked.label.isNotEmpty ? picked.label : 'Ext ${picked.extension}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Add Contact' : 'Edit Contact'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone / Extension *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
                if (widget.batchExtensions.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.list),
                    tooltip: 'Pick from batch',
                    onPressed: _pickFromBatch,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _groupCtrl,
              decoration: const InputDecoration(
                labelText: 'Group',
                hintText: 'All Contacts',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final phone = _phoneCtrl.text.trim();
            if (name.isEmpty || phone.isEmpty) return;
            Navigator.pop(
              context,
              PhonebookEntry(
                name: name,
                phone: phone,
                group: _groupCtrl.text.trim().isEmpty
                    ? 'All Contacts'
                    : _groupCtrl.text.trim(),
              ),
            );
          },
          child: Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
