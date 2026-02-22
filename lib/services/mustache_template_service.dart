import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

enum TemplateSource { bundled, customOverride, customNew }

class TemplateInfo {
  final String key;
  final String displayName;
  final String contentType;
  final TemplateSource source;

  const TemplateInfo({
    required this.key,
    required this.displayName,
    required this.contentType,
    required this.source,
  });
}

class MustacheTemplateService {
  static final MustacheTemplateService instance = MustacheTemplateService._();
  MustacheTemplateService._();

  static const Map<String, String> bundledTemplates = {
    'yealink_t4x': 'assets/templates/yealink_t4x.cfg.mustache',
    'polycom_vvx': 'assets/templates/polycom_vvx.xml.mustache',
    'cisco_88xx': 'assets/templates/cisco_88xx.xml.mustache',
  };

  static const Map<String, String> contentTypes = {
    'yealink_t4x': 'text/plain',
    'polycom_vvx': 'application/xml',
    'cisco_88xx': 'application/xml',
  };

  static const Map<String, String> displayNames = {
    'yealink_t4x': 'Yealink T3x/T4x/T5x',
    'polycom_vvx': 'Polycom VVX / Poly Edge',
    'cisco_88xx': 'Cisco 78xx/88xx SIP',
  };

  Future<Directory> _customDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'custom_templates'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _customFile(String templateKey) async {
    final dir = await _customDir();
    return File(p.join(dir.path, '$templateKey.mustache'));
  }

  /// Loads a template, preferring user-imported custom files over bundled assets.
  Future<String> loadTemplate(String templateKey) async {
    final customFile = await _customFile(templateKey);
    if (await customFile.exists()) {
      return customFile.readAsString();
    }
    final assetPath = bundledTemplates[templateKey];
    if (assetPath != null) {
      return rootBundle.loadString(assetPath);
    }
    throw ArgumentError('Unknown template key: $templateKey');
  }

  /// Returns the HTTP Content-Type for the given template key.
  String getContentType(String templateKey) {
    return contentTypes[templateKey] ?? 'text/plain';
  }

  /// Copies an external file into the custom templates directory.
  Future<void> importCustomTemplate(String sourceFilePath, String templateKey) async {
    final source = File(sourceFilePath);
    final dest = await _customFile(templateKey);
    await source.copy(dest.path);
  }

  /// Saves raw Mustache content as a custom template file.
  Future<void> saveCustomTemplate(String templateKey, String content) async {
    final file = await _customFile(templateKey);
    await file.writeAsString(content);
  }

  /// Writes the template to a temp file and shares it via share_plus.
  Future<void> exportTemplate(String templateKey) async {
    final content = await loadTemplate(templateKey);
    final tmpDir = await getTemporaryDirectory();
    final isXml = (contentTypes[templateKey] ?? 'text/plain') == 'application/xml';
    final fileName = '$templateKey.${isXml ? 'xml' : 'cfg'}.mustache';
    final tmpFile = File(p.join(tmpDir.path, fileName));
    await tmpFile.writeAsString(content);
    await Share.shareXFiles(
      [XFile(tmpFile.path)],
      text: 'Pocket Provisioner Template: ${displayNames[templateKey] ?? templateKey}',
    );
  }

  /// Returns all templates — bundled defaults plus any custom overrides or new custom templates.
  Future<List<TemplateInfo>> listAll() async {
    final result = <TemplateInfo>[];
    final customDir = await _customDir();

    for (final key in bundledTemplates.keys) {
      final customFile = File(p.join(customDir.path, '$key.mustache'));
      final hasCustom = await customFile.exists();
      result.add(TemplateInfo(
        key: key,
        displayName: displayNames[key] ?? key,
        contentType: contentTypes[key] ?? 'text/plain',
        source: hasCustom ? TemplateSource.customOverride : TemplateSource.bundled,
      ));
    }

    // Find custom-new templates not covered by bundledTemplates
    if (await customDir.exists()) {
      try {
        final files = customDir.listSync().whereType<File>();
        for (final file in files) {
          final basename = p.basename(file.path);
          final key = basename.endsWith('.mustache')
              ? basename.substring(0, basename.length - '.mustache'.length)
              : basename;
          if (!bundledTemplates.containsKey(key)) {
            result.add(TemplateInfo(
              key: key,
              displayName: key,
              contentType: 'text/plain',
              source: TemplateSource.customNew,
            ));
          }
        }
      } catch (e) {
        // Directory listing failed (e.g. permissions). Bundled templates are
        // still returned above; custom-new entries are simply omitted.
        debugPrint('MustacheTemplateService: listSync error: $e');
      }
    }

    return result;
  }

  /// Deletes a custom template file. Bundled templates cannot be deleted.
  Future<void> deleteCustomTemplate(String templateKey) async {
    final file = await _customFile(templateKey);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
