import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../data/device_templates.dart';
import '../models/device.dart';

/// Displays all PENDING devices and lets the user:
///   - Tap a device to select it as the next scan target (pops with the Device).
///   - Edit the model for any individual device via the edit icon.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List<Device> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final devices = await DatabaseHelper.instance.getPendingDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _loading = false;
      });
    }
  }

  Future<void> _editModel(Device device) async {
    String selectedModel = DeviceTemplates.supportedModels.contains(device.model)
        ? device.model
        : DeviceTemplates.supportedModels.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Change Model — Ext ${device.extension}'),
          content: DropdownButtonFormField<String>(
            value: selectedModel,
            decoration: const InputDecoration(
              labelText: 'Device Model',
              border: OutlineInputBorder(),
            ),
            items: DeviceTemplates.supportedModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setDialogState(() => selectedModel = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    await DatabaseHelper.instance.updateDeviceModel(device.id!, selectedModel);
    _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? const Center(child: Text('No pending devices'))
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(device.extension),
                          ),
                        ),
                      ),
                      title: Text(device.label),
                      subtitle: Text('Model: ${device.model}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Change Model',
                        onPressed: () => _editModel(device),
                      ),
                      onTap: () => Navigator.pop(context, device),
                    );
                  },
                ),
    );
  }
}
