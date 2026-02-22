import 'package:flutter/material.dart';
import '../data/device_templates.dart';
import '../models/button_key.dart';
import '../models/device.dart';
import 'button_layout_editor.dart';

/// Visual, interactive handset diagram button-layout editor.
///
/// Renders a stylised phone body with each programmable key in its
/// approximate physical position. Tapping a key opens [KeyEditDialog]
/// to configure its type / value / label via dropdowns, exactly like the
/// grid editor — but now spatially tied to where the button lives on the
/// real handset.
///
/// Returns the modified [List<ButtonKey>] via [Navigator.pop].
class PhysicalButtonEditorScreen extends StatefulWidget {
  final String extension;
  final String label;
  final String model;
  final List<ButtonKey> initialLayout;
  final List<({String extension, String label})> batchExtensions;

  const PhysicalButtonEditorScreen({
    super.key,
    required this.extension,
    required this.label,
    required this.model,
    required this.initialLayout,
    this.batchExtensions = const [],
  });

  @override
  State<PhysicalButtonEditorScreen> createState() =>
      _PhysicalButtonEditorScreenState();
}

class _PhysicalButtonEditorScreenState
    extends State<PhysicalButtonEditorScreen> {
  late List<ButtonKey> _layout;

  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout.map((k) => k.clone()).toList();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  ButtonKey _keyById(int id) =>
      _layout.firstWhere((k) => k.id == id, orElse: () => ButtonKey(id));

  Color _keyColor(ButtonKey k) {
    if (k.type == 'none') return Colors.grey.shade700;
    return switch (k.type) {
      'blf'       => Colors.green.shade700,
      'line'      => Colors.blue.shade700,
      'speeddial' => Colors.orange.shade700,
      'dtmf'      => Colors.purple.shade700,
      'park'      => Colors.teal.shade700,
      _           => Colors.blueGrey.shade700,
    };
  }

  Future<void> _editKey(int keyId) async {
    // Ensure the key exists in _layout; add if not.
    if (!_layout.any((k) => k.id == keyId)) {
      setState(() => _layout.add(ButtonKey(keyId)));
    }
    final key = _keyById(keyId);

    final csvDevices = widget.batchExtensions
        .map((e) => Device(
              model: '',
              extension: e.extension,
              secret: '',
              label: e.label,
            ))
        .toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.extension) ?? 0;
        final bNum = int.tryParse(b.extension) ?? 0;
        return aNum.compareTo(bNum);
      });

    await showDialog(
      context: context,
      builder: (_) => KeyEditDialog(
        key_: key,
        csvDevices: csvDevices,
        onSave: (_) => setState(() {}),
      ),
    );
  }

  // ── key button widget ──────────────────────────────────────────────────────

  Widget _keyButton(int keyId, {double? width, double? height}) {
    final key = _keyById(keyId);
    final color = _keyColor(key);
    final isProgrammed = key.type != 'none';

    return GestureDetector(
      onTap: () => _editKey(keyId),
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isProgrammed ? Colors.white30 : Colors.white10,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$keyId',
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 8,
                  fontWeight: FontWeight.bold),
            ),
            if (isProgrammed) ...[
              Text(
                key.type.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              if (key.label.isNotEmpty)
                Text(
                  key.label,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 7),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              else if (key.value.isNotEmpty)
                Text(
                  key.value,
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 7),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
            ] else
              const Text('—',
                  style: TextStyle(color: Colors.white24, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── phone diagram ──────────────────────────────────────────────────────────

  Widget _buildPhoneDiagram(PhysicalLayout layout, BoxConstraints constraints) {
    // Responsive sizing — phone fills available height with a portrait ratio.
    const double phoneAspect = 0.52; // width / height
    final double phoneH = constraints.maxHeight;
    final double phoneW = (phoneH * phoneAspect).clamp(0.0, constraints.maxWidth);
    final Color bodyColor = Color(layout.bodyColorValue);
    final Color screenBg = Colors.grey.shade900;

    // Key column width ≈ 16% of phone width; screen gets the rest.
    final double colW = phoneW * 0.16;

    // Build a key column for [ids] (top-to-bottom list of key IDs).
    Widget keyColumn(List<int> ids) => SizedBox(
      width: colW,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ids
            .map((id) => Flexible(child: _keyButton(id, width: colW)))
            .toList(),
      ),
    );

    // Screen content — shows a simple "dial display" mock.
    Widget screen = Container(
      decoration: BoxDecoration(
        color: screenBg,
        borderRadius: BorderRadius.circular(4),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, color: Colors.green.shade400, size: 22),
            const SizedBox(height: 4),
            Text(
              'Ext ${widget.extension}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11),
            ),
            Text(
              widget.label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              widget.model,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 8),
            ),
          ],
        ),
      ),
    );

    // Left and right key IDs.
    final leftIds =
        List.generate(layout.leftKeyCount, (i) => i + 1);
    final rightIds = List.generate(
        layout.rightKeyCount, (i) => layout.leftKeyCount + i + 1);

    // Soft-key row at the bottom of the screen.
    Widget softKeyRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        4,
        (i) => _SoftKeyButton(label: ['Menu', 'Dir', 'DND', 'History'][i]),
      ),
    );

    // Nav cluster mock (not tappable — these are not programmable).
    Widget navCluster = Center(
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 16,
              child: _NavBtn(icon: Icons.keyboard_arrow_up),
            ),
            Positioned(
              bottom: 0,
              left: 16,
              child: _NavBtn(icon: Icons.keyboard_arrow_down),
            ),
            Positioned(
              left: 0,
              top: 16,
              child: _NavBtn(icon: Icons.keyboard_arrow_left),
            ),
            Positioned(
              right: 0,
              top: 16,
              child: _NavBtn(icon: Icons.keyboard_arrow_right),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: _NavBtn(icon: Icons.circle, size: 20),
            ),
          ],
        ),
      ),
    );

    // Dial pad (12 keys).
    Widget dialPad = GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1.8,
      children: [
        '1', '2', '3',
        '4', '5', '6',
        '7', '8', '9',
        '*', '0', '#',
      ]
          .map((d) => Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(d,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ),
              ))
          .toList(),
    );

    return Center(
      child: SizedBox(
        width: phoneW,
        height: phoneH,
        child: Container(
          decoration: BoxDecoration(
            color: bodyColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Column(
            children: [
              // Speaker grille
              _SpeakerGrille(),
              const SizedBox(height: 4),

              // Main area: left keys + screen + right keys
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (layout.leftKeyCount > 0) keyColumn(leftIds),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: screen),
                          if (layout.hasSoftKeys) ...[
                            const SizedBox(height: 3),
                            softKeyRow,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 3),
                    if (layout.rightKeyCount > 0) keyColumn(rightIds),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Nav cluster
              if (layout.hasNavCluster) ...[
                navCluster,
                const SizedBox(height: 4),
              ],

              // Dial pad
              if (layout.hasDialPad) ...[
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: dialPad,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = DeviceTemplates.getPhysicalLayout(widget.model);
    final programmed = _layout.where((k) => k.type != 'none').length;
    final physical = layout.totalKeyCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Visual Layout',
                style: TextStyle(fontSize: 16)),
            Text(
              'Ext ${widget.extension}  —  ${widget.label}  •  ${widget.model}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save layout',
            onPressed: () => Navigator.pop(context, _layout),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Legend + hint bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '$programmed / $physical physical keys programmed',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  _LegendDot(color: Colors.green.shade700, label: 'BLF'),
                  _LegendDot(color: Colors.blue.shade700, label: 'Line'),
                  _LegendDot(
                      color: Colors.orange.shade700, label: 'Speed'),
                  _LegendDot(
                      color: Colors.grey.shade700, label: 'Empty'),
                ],
              ),
            ),
            // Phone diagram
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildPhoneDiagram(layout, constraints),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── small helper widgets ──────────────────────────────────────────────────────

class _SpeakerGrille extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
}

class _SoftKeyButton extends StatelessWidget {
  final String label;
  const _SoftKeyButton({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 8)),
      );
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  const _NavBtn({required this.icon, this.size = 18});

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: size * 0.7, color: Colors.white70),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: Colors.grey)),
          ],
        ),
      );
}
