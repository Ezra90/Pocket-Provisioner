import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/database_helper.dart';
import '../services/button_layout_service.dart';
import '../models/device.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  Device? _target;
  bool _isProcessing = false;
  int _pendingCount = 0;
  bool _carryOverLayout = false;

  @override
  void initState() {
    super.initState();
    _loadNextTarget();
    _loadCarryOverSettings();
  }

  Future<void> _loadCarryOverSettings() async {
    final settings = await ButtonLayoutService.getCarryOverSettings();
    if (mounted) setState(() => _carryOverLayout = settings['button_layout'] ?? false);
  }

  Future<void> _loadNextTarget() async {
    final next = await DatabaseHelper.instance.getNextPendingDevice();
    final count = await DatabaseHelper.instance.getPendingCount();
    setState(() {
      _target = next;
      _isProcessing = false;
      _pendingCount = count;
    });
  }

  /// Shows a streamlined dialog to customise per-handset button labels when
  /// the button layout is being carried over.
  Future<void> _showCustomiseLabelsDialog(String mac, String model) async {
    final layout = await ButtonLayoutService.getLayoutForModel(model);
    final activeKeys = layout.where((k) => k.type != 'none' && k.value.isNotEmpty).toList();
    if (activeKeys.isEmpty) return;

    // Load any existing overrides for this MAC
    final existingOverrides = await ButtonLayoutService.getLabelOverrides(mac);
    final Map<int, TextEditingController> controllers = {
      for (final k in activeKeys)
        k.id: TextEditingController(
          text: existingOverrides[k.id.toString()] ?? k.label,
        ),
    };

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Customise Labels"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "The button layout is being carried over. "
                "Edit any labels for this handset, or tap Skip to keep defaults.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ...activeKeys.map((k) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: controllers[k.id],
                      decoration: InputDecoration(
                        labelText: "Key "+k.id.toString()+" — "+k.type.toUpperCase()+" "+k.value,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Skip (use defaults)"),
          ),
          ElevatedButton(
            onPressed: () async {
              final overrides = <String, String>{
                for (final k in activeKeys)
                  k.id.toString(): controllers[k.id]!.text.trim(),
              };
              await ButtonLayoutService.saveLabelOverrides(mac, overrides);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Save Labels"),
          ),
        ],
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _showConfirmationDialog(String cleanMac) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Assignment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Matched MAC: $cleanMac → Extension: ${_target!.extension} (${_target!.label})",
            ),
            if (_carryOverLayout) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.content_copy, size: 14, color: Colors.orange),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        "Button layout carry-over is ON — you'll be able to customise labels after confirming.",
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isProcessing = false);
            },
            child: const Text("Rescan / Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              try {
                await DatabaseHelper.instance.assignMac(_target!.id!, cleanMac);
                if (mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("SUCCESS — $cleanMac assigned!"),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
                // Show label customisation if carry-over layout is active
                if (_carryOverLayout && mounted) {
                  await _showCustomiseLabelsDialog(cleanMac, _target!.model);
                }
                _loadNextTarget();
              } catch (e) {
                if (mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Error saving assignment: $e"),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  setState(() => _isProcessing = false);
                }
              }
            },
            child: const Text("Confirm & Next"),
          ),
        ],
      ),
    );
    // Safety net: ensure scanner is re-enabled if dialog closed unexpectedly
    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_target == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Job Complete")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              const Text("All Devices Assigned!", style: TextStyle(fontSize: 24)),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text("Return to Dashboard")
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Scan Barcode")),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "📋 Pending: $_pendingCount devices remaining",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (_carryOverLayout)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.content_copy, size: 14, color: Colors.deepOrange),
                  SizedBox(width: 6),
                  Text(
                    "Button layout carry-over is ON",
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Colors.blueAccent,
            child: Column(
              children: [
                const Text("SCANNING FOR:", style: TextStyle(color: Colors.white70, letterSpacing: 1.5)),
                const SizedBox(height: 5),
                Text(
                  _target!.label, 
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                Text("Model: ${_target!.model}", style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          
          Expanded(
            child: MobileScanner(
              onDetect: (capture) async {
                if (_isProcessing) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final String? rawMac = barcodes.first.rawValue;
                if (rawMac == null || rawMac.length < 10) return;

                setState(() => _isProcessing = true);
                final String cleanMac = rawMac.replaceAll(':', '').toUpperCase();
                if (mounted) await _showConfirmationDialog(cleanMac);
              },
            ),
          ),
        ],
      ),
    );
  }
}
