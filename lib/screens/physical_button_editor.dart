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
/// Three rendering modes are supported, selected automatically from the
/// [PhysicalLayout]:
///   • Mode A – VVX 1500 landscape touchscreen
///   • Mode B – T48G / T57W portrait touchscreen
///   • Mode C – physical key models (with optional page navigation)
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

  /// Expand/collapse state for touchscreen models (Modes A & B).
  bool _isExpanded = false;

  /// Current page for paginated physical-key models (Mode C, 0-indexed).
  int _currentPage = 0;

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
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 3,
              offset: Offset(0, 2),
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

  // ── phone diagram dispatcher ───────────────────────────────────────────────

  Widget _buildPhoneDiagram(PhysicalLayout layout, BoxConstraints constraints) {
    if (layout.isLandscape) {
      return _buildVVX1500Diagram(layout, constraints);
    } else if (layout.isTouchscreen) {
      return _buildTouchscreenDiagram(layout, constraints);
    } else {
      return _buildPhysicalKeyDiagram(layout, constraints);
    }
  }

  // ── Mode A: VVX 1500 landscape touchscreen ────────────────────────────────

  Widget _buildVVX1500Diagram(
      PhysicalLayout layout, BoxConstraints constraints) {
    // Maintain ~1.67:1 (800×480) landscape aspect ratio.
    const double aspect = 1.67;
    final double phoneW, phoneH;
    if (constraints.maxWidth / constraints.maxHeight >= aspect) {
      phoneH = constraints.maxHeight;
      phoneW = phoneH * aspect;
    } else {
      phoneW = constraints.maxWidth;
      phoneH = phoneW / aspect;
    }

    final Color bodyColor = Color(layout.bodyColorValue);
    final double rightColW = phoneW * 0.18;
    // Overlay covers roughly 40 % of the screen area when expanded.
    final double overlayW = (phoneW - rightColW) * 0.45;

    // Initial visible key IDs in the right column.
    final int colCount =
        layout.initialVisibleKeys > 0 ? layout.initialVisibleKeys : 6;
    final rightColIds = List.generate(colCount, (i) => i + 1);

    // Keys shown in the overlay grid (everything beyond the right column).
    final overlayIds = List.generate(
      layout.totalKeyCount - colCount,
      (i) => colCount + i + 1,
    );

    // ── Right column ────────────────────────────────────────────────────────
    Widget rightColumn = SizedBox(
      width: rightColW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Key slots with LED dots
          ...rightColIds.map((id) {
            final k = _keyById(id);
            final active = k.type != 'none';
            return Expanded(
              child: Row(
                children: [
                  // LED status dot
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 2, right: 3),
                    decoration: BoxDecoration(
                      color: active ? Colors.green : Colors.grey.shade700,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(child: _keyButton(id)),
                ],
              ),
            );
          }),
          // More / Close toggle button
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              height: 22,
              margin: const EdgeInsets.only(top: 2, bottom: 2, left: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  _isExpanded
                      ? (layout.collapseButtonLabel.isNotEmpty
                          ? layout.collapseButtonLabel
                          : 'Close')
                      : (layout.expandButtonLabel.isNotEmpty
                          ? layout.expandButtonLabel
                          : 'More'),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 9),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // ── Screen / main area ──────────────────────────────────────────────────
    Widget screenArea = Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background: status bar + wallpaper placeholder
              Column(
                children: [
                  Container(
                    height: 20,
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_none,
                            color: Colors.white60, size: 12),
                        const Spacer(),
                        Text(
                          'Ext ${widget.extension}',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                            color: Colors.white12, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
              // Overlay panel shown when expanded
              if (_isExpanded)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: overlayW,
                  child: Container(
                    color: Colors.black.withOpacity(0.88),
                    padding: const EdgeInsets.all(4),
                    child: GridView.count(
                      crossAxisCount: 2,
                      childAspectRatio: 2.2,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                      physics: const NeverScrollableScrollPhysics(),
                      children: overlayIds
                          .take(20)
                          .map((id) => _keyButton(id))
                          .toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // ── Bottom soft-key bar ─────────────────────────────────────────────────
    final softLabels = layout.softKeyLabels.isNotEmpty
        ? layout.softKeyLabels
        : const <String>['New Call', 'Forward', 'MyStat', 'Buddies'];

    Widget softKeyBar = Container(
      height: 26,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children:
            softLabels.map((l) => _SoftKeyButton(label: l)).toList(),
      ),
    );

    return Center(
      child: SizedBox(
        width: phoneW,
        height: phoneH,
        child: Container(
          decoration: BoxDecoration(
            color: bodyColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54,
                  blurRadius: 12,
                  offset: Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Column(
            children: [
              // Main area: screen + right column
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    screenArea,
                    const SizedBox(width: 4),
                    rightColumn,
                  ],
                ),
              ),
              const SizedBox(height: 4),
              softKeyBar,
            ],
          ),
        ),
      ),
    );
  }

  // ── Mode B: portrait touchscreen (T48G / T57W / T58W) ────────────────────

  Widget _buildTouchscreenDiagram(
      PhysicalLayout layout, BoxConstraints constraints) {
    const double phoneAspect = 0.52;
    final double phoneH = constraints.maxHeight;
    final double phoneW =
        (phoneH * phoneAspect).clamp(0.0, constraints.maxWidth);
    final Color bodyColor = Color(layout.bodyColorValue);
    final double colW = phoneW * 0.20;

    // ── Common widgets reused in both collapsed and expanded states ──────────

    // Screen content placeholder (shown in collapsed centre area).
    Widget screenContent = Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(4),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, color: Colors.green.shade400, size: 20),
            const SizedBox(height: 4),
            Text(
              'Ext ${widget.extension}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            Text(
              widget.label,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    // ── Key area ────────────────────────────────────────────────────────────
    Widget keyArea;
    if (_isExpanded) {
      // Expanded: 4-column grid of all keys.
      final allIds = List.generate(layout.totalKeyCount, (i) => i + 1);
      keyArea = Column(
        children: [
          // "Show Less" button at the top of the grid
          GestureDetector(
            onTap: () => setState(() => _isExpanded = false),
            child: Container(
              height: 24,
              color: Colors.teal.shade800,
              child: Center(
                child: Text(
                  layout.collapseButtonLabel.isNotEmpty
                      ? layout.collapseButtonLabel
                      : '— Show Less',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1.4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              physics: const NeverScrollableScrollPhysics(),
              children: allIds.map((id) => _keyButton(id)).toList(),
            ),
          ),
        ],
      );
    } else {
      // Collapsed: left column + screen + right column + expand button.
      final leftIds =
          List.generate(layout.leftKeyCount, (i) => i + 1);
      final rightIds = List.generate(
          layout.rightKeyCount, (i) => layout.leftKeyCount + i + 1);

      keyArea = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left key column
          SizedBox(
            width: colW,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: leftIds
                  .map((id) =>
                      Flexible(child: _keyButton(id, width: colW)))
                  .toList(),
            ),
          ),
          const SizedBox(width: 2),
          // Screen wallpaper
          Expanded(child: screenContent),
          const SizedBox(width: 2),
          // Right key column + expand button
          SizedBox(
            width: colW,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...rightIds.map((id) =>
                    Flexible(child: _keyButton(id, width: colW))),
                // Expand button
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = true),
                  child: Container(
                    width: colW,
                    height: 22,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        layout.expandButtonLabel.isNotEmpty
                            ? layout.expandButtonLabel
                            : '+ More',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 7),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── Bottom soft-key bar ─────────────────────────────────────────────────
    final softLabels = layout.softKeyLabels.isNotEmpty
        ? layout.softKeyLabels
        : const <String>['Menu', 'Dir', 'DND', 'History'];

    // Assign distinct colours to each soft key.
    const softKeyColors = [
      Colors.teal,
      Color(0xFFFFC107), // amber / gold
      Colors.red,
      Colors.blue,
    ];

    Widget softKeyBar = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(softLabels.length, (i) {
        final color = softKeyColors[i % softKeyColors.length];
        return _ColoredSoftKey(
          label: softLabels[i],
          color: color,
        );
      }),
    );

    // ── Nav cluster ─────────────────────────────────────────────────────────
    Widget navCluster = Center(
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          children: [
            Positioned(
                top: 0,
                left: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_up)),
            Positioned(
                bottom: 0,
                left: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_down)),
            Positioned(
                left: 0,
                top: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_left)),
            Positioned(
                right: 0,
                top: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_right)),
            Positioned(
                left: 16,
                top: 16,
                child: _NavBtn(icon: Icons.circle, size: 20)),
          ],
        ),
      ),
    );

    // ── Dial pad ─────────────────────────────────────────────────────────────
    Widget dialPad = GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1.8,
      children: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#']
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
                  color: Colors.black54,
                  blurRadius: 12,
                  offset: Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Column(
            children: [
              _SpeakerGrille(),
              const SizedBox(height: 2),
              // Status bar
              Container(
                height: 16,
                color: Colors.black38,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Text(widget.model,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 9)),
                    const Spacer(),
                    const Text('12:00',
                        style: TextStyle(
                            color: Colors.white60, fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // Key area (touchscreen)
              Expanded(flex: 5, child: keyArea),
              const SizedBox(height: 4),
              // Bottom soft-key bar
              if (layout.softKeysAreCustomizable)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Soft keys are customizable via provisioning',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 7),
                  ),
                ),
              softKeyBar,
              const SizedBox(height: 6),
              // Nav cluster
              if (layout.hasNavCluster) ...[
                navCluster,
                const SizedBox(height: 4),
              ],
              // Dial pad
              if (layout.hasDialPad)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    child: dialPad,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mode C: physical key models (with optional pagination) ────────────────

  Widget _buildPhysicalKeyDiagram(
      PhysicalLayout layout, BoxConstraints constraints) {
    const double phoneAspect = 0.52;
    final double phoneH = constraints.maxHeight;
    final double phoneW =
        (phoneH * phoneAspect).clamp(0.0, constraints.maxWidth);
    final Color bodyColor = Color(layout.bodyColorValue);
    final Color screenBg = Colors.grey.shade900;
    final double colW = phoneW * 0.16;

    // Compute which key IDs belong to the current page.
    final int keysPerPage = layout.keysPerPage; // leftKeyCount + rightKeyCount
    final int pageStart = _currentPage * keysPerPage + 1;
    final leftIds = List.generate(
            layout.leftKeyCount, (i) => pageStart + i)
        .where((id) => id <= layout.totalKeyCount)
        .toList();
    final rightIds = List.generate(
            layout.rightKeyCount, (i) => pageStart + layout.leftKeyCount + i)
        .where((id) => id <= layout.totalKeyCount)
        .toList();

    // Build a key column for [ids] (top-to-bottom list of key IDs).
    Widget keyColumn(List<int> ids) => SizedBox(
          width: colW,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ids
                .map((id) =>
                    Flexible(child: _keyButton(id, width: colW)))
                .toList(),
          ),
        );

    // Screen content — simple "dial display" mock.
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

    // Page navigation row (only when keyPages > 1).
    Widget? pageNav;
    if (layout.keyPages > 1) {
      pageNav = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
                minWidth: 28, minHeight: 28),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          Text(
            'Page ${_currentPage + 1}/${layout.keyPages}',
            style: const TextStyle(
                fontSize: 11, color: Colors.white70),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
                minWidth: 28, minHeight: 28),
            onPressed: _currentPage < layout.keyPages - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      );
    }

    // Soft-key row.
    Widget softKeyRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        4,
        (i) => _SoftKeyButton(
            label: ['Menu', 'Dir', 'DND', 'History'][i]),
      ),
    );

    // Nav cluster.
    Widget navCluster = Center(
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          children: [
            Positioned(
                top: 0,
                left: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_up)),
            Positioned(
                bottom: 0,
                left: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_down)),
            Positioned(
                left: 0,
                top: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_left)),
            Positioned(
                right: 0,
                top: 16,
                child: _NavBtn(icon: Icons.keyboard_arrow_right)),
            Positioned(
                left: 16,
                top: 16,
                child: _NavBtn(icon: Icons.circle, size: 20)),
          ],
        ),
      ),
    );

    // Dial pad.
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
                  color: Colors.black54,
                  blurRadius: 12,
                  offset: Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Column(
            children: [
              // Speaker grille
              _SpeakerGrille(),
              const SizedBox(height: 4),

              // Page navigation (when applicable)
              if (pageNav != null) ...[
                pageNav,
                const SizedBox(height: 2),
              ],

              // Main area: left keys + screen + right keys
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leftIds.isNotEmpty) keyColumn(leftIds),
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
                    if (rightIds.isNotEmpty) keyColumn(rightIds),
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
              if (layout.hasDialPad)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    child: dialPad,
                  ),
                ),
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
    final total = layout.totalKeyCount;

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
                    '$programmed / $total keys programmed',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  _LegendDot(
                      color: Colors.green.shade700, label: 'BLF'),
                  _LegendDot(
                      color: Colors.blue.shade700, label: 'Line'),
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
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
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

/// Coloured icon soft key used on T48G / T57W touchscreen models.
class _ColoredSoftKey extends StatelessWidget {
  final String label;
  final Color color;
  const _ColoredSoftKey({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 7),
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
