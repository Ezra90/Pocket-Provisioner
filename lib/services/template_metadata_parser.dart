import 'dart:convert';
import 'mustache_template_service.dart';

/// Metadata for a single template variable.
class TemplateVariableMeta {
  final String name;
  final String category;
  final String description;
  final String example;
  final String defaultValue;

  const TemplateVariableMeta({
    required this.name,
    required this.category,
    required this.description,
    required this.example,
    required this.defaultValue,
  });

  factory TemplateVariableMeta.fromJson(Map<String, dynamic> m) =>
      TemplateVariableMeta(
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? 'sip',
        description: m['description'] as String? ?? '',
        example: m['example'] as String? ?? '',
        defaultValue: m['default'] as String? ?? '',
      );
}

/// Metadata for a category grouping.
class TemplateCategoryMeta {
  final String id;
  final String label;
  final String icon;
  final int order;

  const TemplateCategoryMeta({
    required this.id,
    required this.label,
    required this.icon,
    required this.order,
  });

  factory TemplateCategoryMeta.fromJson(Map<String, dynamic> m) =>
      TemplateCategoryMeta(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        icon: m['icon'] as String? ?? '',
        order: (m['order'] as num?)?.toInt() ?? 99,
      );
}

/// SVG schematic dimensions for the handset chassis and screen area.
class SchematicMeta {
  final int chassisWidth;
  final int chassisHeight;
  final int screenX;
  final int screenY;
  final int screenWidth;
  final int screenHeight;

  const SchematicMeta({
    required this.chassisWidth,
    required this.chassisHeight,
    required this.screenX,
    required this.screenY,
    required this.screenWidth,
    required this.screenHeight,
  });

  factory SchematicMeta.fromJson(Map<String, dynamic> m) => SchematicMeta(
        chassisWidth: (m['chassis_width'] as num?)?.toInt() ?? 340,
        chassisHeight: (m['chassis_height'] as num?)?.toInt() ?? 540,
        screenX: (m['screen_x'] as num?)?.toInt() ?? 65,
        screenY: (m['screen_y'] as num?)?.toInt() ?? 58,
        screenWidth: (m['screen_width'] as num?)?.toInt() ?? 210,
        screenHeight: (m['screen_height'] as num?)?.toInt() ?? 150,
      );
}

/// Axis-aligned rect used for chrome (nav cluster, dial pad, etc.).
class LayoutRectMeta {
  final int x;
  final int y;
  final int width;
  final int height;

  const LayoutRectMeta({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory LayoutRectMeta.fromJson(Map<String, dynamic> m) => LayoutRectMeta(
        x: (m['x'] as num?)?.toInt() ?? 0,
        y: (m['y'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 0,
        height: (m['height'] as num?)?.toInt() ?? 0,
      );
}

/// Position data for a single programmable key in the SVG visual editor.
class VisualEditorKey {
  final int index;
  final int x;
  final int y;
  final int width;
  final int height;
  final int page;
  final String side;
  final String role;

  const VisualEditorKey({
    required this.index,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.page,
    required this.side,
    this.role = 'line',
  });

  factory VisualEditorKey.fromJson(Map<String, dynamic> m) => VisualEditorKey(
        index: (m['index'] as num?)?.toInt() ?? 0,
        x: (m['x'] as num?)?.toInt() ?? 0,
        y: (m['y'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 44,
        height: (m['height'] as num?)?.toInt() ?? 24,
        page: (m['page'] as num?)?.toInt() ?? 1,
        side: m['side'] as String? ?? 'left',
        role: m['role'] as String? ?? 'line',
      );
}

/// Non-programmable page-switcher chrome (e.g. Yealink bottom-right DSS).
class PageSwitcherMeta {
  final int x;
  final int y;
  final int width;
  final int height;
  final String label;

  const PageSwitcherMeta({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.label = 'Page',
  });

  factory PageSwitcherMeta.fromJson(Map<String, dynamic> m) => PageSwitcherMeta(
        x: (m['x'] as num?)?.toInt() ?? 0,
        y: (m['y'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 42,
        height: (m['height'] as num?)?.toInt() ?? 22,
        label: m['label'] as String? ?? 'Page',
      );
}

/// Soft-key (under-screen) control — hardware or on-screen.
class SoftKeyMeta {
  final int? index;
  final int x;
  final int y;
  final int width;
  final int height;
  final String label;
  final bool programmable;

  const SoftKeyMeta({
    this.index,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
    this.programmable = false,
  });

  factory SoftKeyMeta.fromJson(Map<String, dynamic> m) => SoftKeyMeta(
        index: (m['index'] as num?)?.toInt(),
        x: (m['x'] as num?)?.toInt() ?? 0,
        y: (m['y'] as num?)?.toInt() ?? 0,
        width: (m['width'] as num?)?.toInt() ?? 48,
        height: (m['height'] as num?)?.toInt() ?? 20,
        label: m['label'] as String? ?? '',
        programmable: m['programmable'] as bool? ?? false,
      );
}

/// Fixed (usually non-editable) handset chrome around the programmable keys.
class ChromeMeta {
  final bool hasSoftKeys;
  final bool hasNavCluster;
  final bool hasDialPad;
  final LayoutRectMeta? navCluster;
  final LayoutRectMeta? dialPad;

  const ChromeMeta({
    this.hasSoftKeys = true,
    this.hasNavCluster = true,
    this.hasDialPad = true,
    this.navCluster,
    this.dialPad,
  });

  factory ChromeMeta.fromJson(Map<String, dynamic> m) => ChromeMeta(
        hasSoftKeys: m['has_soft_keys'] as bool? ?? true,
        hasNavCluster: m['has_nav_cluster'] as bool? ?? true,
        hasDialPad: m['has_dial_pad'] as bool? ?? true,
        navCluster: m['nav_cluster'] is Map<String, dynamic>
            ? LayoutRectMeta.fromJson(m['nav_cluster'] as Map<String, dynamic>)
            : null,
        dialPad: m['dial_pad'] is Map<String, dynamic>
            ? LayoutRectMeta.fromJson(m['dial_pad'] as Map<String, dynamic>)
            : null,
      );
}

/// Visual editor metadata for SVG-based button layout rendering.
class VisualEditorMeta {
  final bool svgFallback;
  final bool expandableLayout;
  final SchematicMeta schematic;
  final int keysPerPage;
  final List<VisualEditorKey> keys;

  /// Decoded chassis SVG markup (from [chassis_svg] or [chassis_svg_b64]).
  /// Prefer base64 in META comments — raw SVG can break Mustache `{{! … }}`.
  final String? chassisSvg;

  final ChromeMeta? chrome;
  final List<SoftKeyMeta> softKeys;
  final PageSwitcherMeta? pageSwitcher;

  const VisualEditorMeta({
    required this.svgFallback,
    required this.expandableLayout,
    required this.schematic,
    required this.keysPerPage,
    required this.keys,
    this.chassisSvg,
    this.chrome,
    this.softKeys = const [],
    this.pageSwitcher,
  });

  /// True when a custom chassis drawing should be used instead of the rounded rect.
  bool get hasChassisSvg => chassisSvg != null && chassisSvg!.trim().isNotEmpty;

  /// Number of distinct pages the keys span.
  int get pageCount {
    if (keys.isEmpty) return 1;
    return keys.fold<int>(1, (max, k) => k.page > max ? k.page : max);
  }

  /// Returns keys for a specific [page] (1-based).
  List<VisualEditorKey> keysForPage(int page) =>
      keys.where((k) => k.page == page).toList();

  /// Decode optional chassis SVG from raw string or base64.
  static String? decodeChassisSvg(Map<String, dynamic> m) {
    final raw = m['chassis_svg'] as String?;
    if (raw != null && raw.trim().isNotEmpty) return raw;

    final b64 = m['chassis_svg_b64'] as String?;
    if (b64 == null || b64.trim().isEmpty) return null;
    try {
      final cleaned = b64.replaceAll(RegExp(r'\s+'), '');
      return utf8.decode(base64Decode(cleaned));
    } catch (_) {
      return null;
    }
  }

  factory VisualEditorMeta.fromJson(Map<String, dynamic> m) {
    final keysJson = m['keys'] as List<dynamic>? ?? [];
    final softJson = m['soft_keys'] as List<dynamic>? ?? [];
    return VisualEditorMeta(
      svgFallback: m['svg_fallback'] as bool? ?? true,
      expandableLayout: m['expandable_layout'] as bool? ?? false,
      schematic: m['schematic'] is Map<String, dynamic>
          ? SchematicMeta.fromJson(m['schematic'] as Map<String, dynamic>)
          : const SchematicMeta(
              chassisWidth: 340,
              chassisHeight: 540,
              screenX: 65,
              screenY: 58,
              screenWidth: 210,
              screenHeight: 150,
            ),
      keysPerPage: (m['keys_per_page'] as num?)?.toInt() ?? 10,
      keys: keysJson
          .map((e) => VisualEditorKey.fromJson(e as Map<String, dynamic>))
          .toList(),
      chassisSvg: decodeChassisSvg(m),
      chrome: m['chrome'] is Map<String, dynamic>
          ? ChromeMeta.fromJson(m['chrome'] as Map<String, dynamic>)
          : null,
      softKeys: softJson
          .map((e) => SoftKeyMeta.fromJson(e as Map<String, dynamic>))
          .toList(),
      pageSwitcher: m['page_switcher'] is Map<String, dynamic>
          ? PageSwitcherMeta.fromJson(m['page_switcher'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Parsed metadata from a `{{! META: {...} }}` comment block.
class TemplateMetadata {
  // ── Device identity ───────────────────────────────────────────────────
  final String manufacturer;
  final String modelFamily;
  final String displayName;
  final String configFormat;
  final String contentType;
  final String filenamePattern;
  final List<String> supportedModels;
  final int maxLineKeys;
  final Map<String, Map<String, int>> wallpaperSpecs;
  final Map<String, int> typeMapping;

  // ── Template structure ────────────────────────────────────────────────
  final List<TemplateCategoryMeta> categories;
  final Map<String, TemplateVariableMeta> variables;

  // ── Visual editor layout ──────────────────────────────────────────────
  final VisualEditorMeta? visualEditor;

  const TemplateMetadata({
    this.manufacturer = '',
    this.modelFamily = '',
    this.displayName = '',
    this.configFormat = '',
    this.contentType = '',
    this.filenamePattern = '',
    this.supportedModels = const [],
    this.maxLineKeys = 0,
    this.wallpaperSpecs = const {},
    this.typeMapping = const {},
    required this.categories,
    required this.variables,
    this.visualEditor,
  });

  /// Default categories matching the existing ExpansionTile sections.
  static const List<TemplateCategoryMeta> defaultCategories = [
    TemplateCategoryMeta(
        id: 'sip', label: 'SIP & Registration', icon: '📞', order: 1),
    TemplateCategoryMeta(
        id: 'display', label: 'Display & Audio', icon: '📱', order: 2),
    TemplateCategoryMeta(
        id: 'security', label: 'Security', icon: '🔑', order: 3),
    TemplateCategoryMeta(
        id: 'network', label: 'Network', icon: '🌐', order: 4),
    TemplateCategoryMeta(
        id: 'call_features', label: 'Call Features', icon: '📲', order: 5),
    TemplateCategoryMeta(
        id: 'provisioning', label: 'Provisioning & Time', icon: '🔧', order: 6),
    TemplateCategoryMeta(
        id: 'diagnostics',
        label: 'Diagnostics & Logs',
        icon: '🔍',
        order: 7),
  ];

  /// Groups variables by their category, sorted by category order.
  Map<TemplateCategoryMeta, List<TemplateVariableMeta>> get groupedByCategory {
    final cats = categories.isEmpty ? defaultCategories : categories;
    final sorted = List<TemplateCategoryMeta>.from(cats)
      ..sort((a, b) => a.order.compareTo(b.order));

    final result = <TemplateCategoryMeta, List<TemplateVariableMeta>>{};
    for (final cat in sorted) {
      final vars = variables.values
          .where((v) => v.category == cat.id)
          .toList();
      if (vars.isNotEmpty) result[cat] = vars;
    }
    return result;
  }

  static const TemplateMetadata empty = TemplateMetadata(
    categories: [],
    variables: {},
  );
}

/// Extracts and parses the `{{! META: {...} }}` JSON block embedded in a
/// Mustache template comment.
class TemplateMetadataParser {
  /// Regex that matches `{{! META: <json> }}` (whitespace-tolerant).
  /// Uses a greedy inner match so the full JSON object is captured rather than
  /// stopping at the first closing brace inside the JSON content.
  static final _metaRegex =
      RegExp(r'\{\{!\s*META:\s*(\{[\s\S]*\})\s*\}\}', multiLine: true);

  /// Loads [templateKey] and extracts its embedded META block.
  /// Returns [TemplateMetadata.empty] if no block is found or parsing fails.
  static Future<TemplateMetadata> parse(String templateKey) async {
    final source =
        await MustacheTemplateService.instance.loadTemplate(templateKey);
    return parseSource(source);
  }

  /// Parses the META block from a raw template [source] string.
  static TemplateMetadata parseSource(String source) {
    final match = _metaRegex.firstMatch(source);
    if (match == null) return TemplateMetadata.empty;

    try {
      final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;

      final categoriesJson = json['categories'] as List<dynamic>? ?? [];
      final categories = categoriesJson
          .map((e) =>
              TemplateCategoryMeta.fromJson(e as Map<String, dynamic>))
          .toList();

      final variablesJson = json['variables'] as List<dynamic>? ?? [];
      final variables = <String, TemplateVariableMeta>{};
      for (final v in variablesJson) {
        final meta =
            TemplateVariableMeta.fromJson(v as Map<String, dynamic>);
        variables[meta.name] = meta;
      }

      // Parse supported_models list
      final modelsJson = json['supported_models'] as List<dynamic>? ?? [];
      final supportedModels = modelsJson.map((e) => e.toString()).toList();

      // Parse wallpaper_specs map
      final wpJson = json['wallpaper_specs'] as Map<String, dynamic>? ?? {};
      final wallpaperSpecs = <String, Map<String, int>>{};
      for (final entry in wpJson.entries) {
        final spec = entry.value as Map<String, dynamic>? ?? {};
        wallpaperSpecs[entry.key] = {
          'width': (spec['width'] as num?)?.toInt() ?? 0,
          'height': (spec['height'] as num?)?.toInt() ?? 0,
        };
      }

      // Parse type_mapping map
      final tmJson = json['type_mapping'] as Map<String, dynamic>? ?? {};
      final typeMapping = <String, int>{};
      for (final entry in tmJson.entries) {
        typeMapping[entry.key] = (entry.value as num?)?.toInt() ?? 0;
      }

      // Parse visual_editor
      VisualEditorMeta? visualEditor;
      if (json['visual_editor'] is Map<String, dynamic>) {
        visualEditor = VisualEditorMeta.fromJson(
            json['visual_editor'] as Map<String, dynamic>);
      }

      return TemplateMetadata(
        manufacturer: json['manufacturer'] as String? ?? '',
        modelFamily: json['model_family'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        configFormat: json['config_format'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        filenamePattern: json['filename_pattern'] as String? ?? '',
        supportedModels: supportedModels,
        maxLineKeys: (json['max_line_keys'] as num?)?.toInt() ?? 0,
        wallpaperSpecs: wallpaperSpecs,
        typeMapping: typeMapping,
        categories: categories,
        variables: variables,
        visualEditor: visualEditor,
      );
    } on FormatException {
      // JSON in the META block is malformed — return empty metadata.
      return TemplateMetadata.empty;
    } on TypeError {
      // Unexpected JSON structure — return empty metadata.
      return TemplateMetadata.empty;
    }
  }
}
