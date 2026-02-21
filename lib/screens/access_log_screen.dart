import 'dart:async';
import 'package:flutter/material.dart';
import '../models/access_log_entry.dart';
import '../services/provisioning_server.dart';

class AccessLogScreen extends StatefulWidget {
  const AccessLogScreen({super.key});

  @override
  State<AccessLogScreen> createState() => _AccessLogScreenState();
}

class _AccessLogScreenState extends State<AccessLogScreen> {
  late StreamSubscription<AccessLogEntry> _subscription;
  // Snapshot rebuilt on every new entry.
  List<AccessLogEntry> _log = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _log = List.of(ProvisioningServer.accessLog);
    _subscription = ProvisioningServer.accessLogStream.listen((_) {
      if (mounted) {
        setState(() {
          _log = List.of(ProvisioningServer.accessLog);
        });
        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build the device-centric summary section.
  // ---------------------------------------------------------------------------
  Widget _buildDeviceSummary() {
    final deviceMap = ProvisioningServer.deviceAccessMap;
    if (deviceMap.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No devices have connected yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Count how many unique MACs have pulled a config
    final configCount = deviceMap.values.where((s) => s.contains('config')).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '$configCount of ${deviceMap.length} device(s) have pulled configs',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...deviceMap.entries.map((entry) {
          final mac = entry.key;
          final types = entry.value;

          // Find last log entry for this MAC to get IP and label
          final deviceEntries = _log.where((e) => e.resolvedMac == mac).toList();
          if (deviceEntries.isEmpty) return const SizedBox.shrink();
          final lastEntry = deviceEntries.last;

          final formattedMac = lastEntry.formattedMac;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              onTap: () => _showDeviceDetail(mac),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.phone_android, size: 20, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedMac,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace'),
                              ),
                              if (lastEntry.deviceLabel != null)
                                Text(
                                  lastEntry.deviceLabel!,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              if (lastEntry.clientIp.isNotEmpty)
                                Text(
                                  lastEntry.clientIp,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.blueGrey),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          _formatTime(lastEntry.timestamp),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildResourceIndicators(types),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResourceIndicators(Set<String> types) {
    const resources = ['config', 'wallpaper', 'template', 'original_media'];
    const labels = {
      'config': 'Config',
      'wallpaper': 'Wallpaper',
      'template': 'Template',
      'original_media': 'Media',
    };
    return Wrap(
      spacing: 8,
      children: resources.map((r) {
        final done = types.contains(r);
        return Chip(
          avatar: Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: done ? Colors.green : Colors.grey,
          ),
          label: Text(
            labels[r] ?? r,
            style: TextStyle(
                fontSize: 12, color: done ? Colors.green : Colors.grey),
          ),
          backgroundColor:
              done ? Colors.green.shade50 : Colors.grey.shade100,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Per-device detail bottom sheet.
  // ---------------------------------------------------------------------------
  void _showDeviceDetail(String mac) {
    final entries = _log.where((e) => e.resolvedMac == mac).toList();
    // entries is always non-empty here: detail is only opened from device cards
    // which are only rendered when deviceEntries.isNotEmpty.
    final formattedMac =
        entries.isNotEmpty ? entries.first.formattedMac : mac;
    final label =
        entries.isNotEmpty ? entries.first.deviceLabel : null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, controller) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formattedMac,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace'),
                            ),
                            if (label != null)
                              Text(label,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isOk = e.statusCode == 200;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isOk ? Icons.check_circle : Icons.error,
                          color: isOk ? Colors.green : Colors.redAccent,
                          size: 20,
                        ),
                        title: Text(
                          e.requestedPath,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                        subtitle: Text(
                          '${e.resourceType} · ${e.statusCode} · ${_formatTime(e.timestamp)}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Raw log section at the bottom.
  // ---------------------------------------------------------------------------
  Widget _buildRawLog() {
    if (_log.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('All Requests',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _log.length,
          itemBuilder: (_, i) {
            final e = _log[i];
            final isOk = e.statusCode == 200;
            return ListTile(
              dense: true,
              leading: Icon(
                isOk ? Icons.check_circle_outline : Icons.error_outline,
                color: isOk ? Colors.green : Colors.redAccent,
                size: 18,
              ),
              title: Text(
                e.requestedPath,
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              subtitle: Text(
                '${e.clientIp}  ${e.resolvedMac != null ? e.formattedMac : '—'}  ${e.statusCode}  ${_formatTime(e.timestamp)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() {
                _log = List.of(ProvisioningServer.accessLog);
              });
            },
          ),
        ],
      ),
      body: _log.isEmpty && ProvisioningServer.deviceAccessMap.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monitor_heart_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Waiting for handsets to connect…',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Make sure the provisioning server is running\nand DHCP Option 66 is configured.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeviceSummary(),
                  const Divider(height: 24),
                  _buildRawLog(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
