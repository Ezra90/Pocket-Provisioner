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

/// Parsed metadata from a `{{! META: {...} }}` comment block.
class TemplateMetadata {
  final List<TemplateCategoryMeta> categories;
  final Map<String, TemplateVariableMeta> variables;

  const TemplateMetadata({
    required this.categories,
    required this.variables,
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
  static final _metaRegex =
      RegExp(r'\{\{!\s*META:\s*(\{[\s\S]*?\})\s*\}\}', multiLine: true);

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

      return TemplateMetadata(
          categories: categories, variables: variables);
    } on FormatException {
      // JSON in the META block is malformed — return empty metadata.
      return TemplateMetadata.empty;
    } on TypeError {
      // Unexpected JSON structure — return empty metadata.
      return TemplateMetadata.empty;
    }
  }
}
