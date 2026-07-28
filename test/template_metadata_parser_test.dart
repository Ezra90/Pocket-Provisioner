import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_provisioner/services/template_metadata_parser.dart';

void main() {
  test('VisualEditorMeta decodes chassis_svg_b64 and chrome/soft_keys', () {
    final ve = VisualEditorMeta.fromJson({
      'svg_fallback': false,
      'expandable_layout': false,
      'chassis_svg_b64':
          // "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"
          'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg==',
      'schematic': {
        'chassis_width': 340,
        'chassis_height': 560,
        'screen_x': 58,
        'screen_y': 42,
        'screen_width': 224,
        'screen_height': 168,
      },
      'keys_per_page': 10,
      'chrome': {
        'has_soft_keys': true,
        'has_nav_cluster': true,
        'has_dial_pad': true,
        'nav_cluster': {'x': 134, 'y': 254, 'width': 72, 'height': 72},
        'dial_pad': {'x': 78, 'y': 350, 'width': 184, 'height': 152},
      },
      'soft_keys': [
        {
          'label': 'Menu',
          'x': 58,
          'y': 220,
          'width': 48,
          'height': 20,
          'programmable': false,
        }
      ],
      'keys': [
        {
          'index': 1,
          'x': 12,
          'y': 52,
          'width': 42,
          'height': 22,
          'page': 1,
          'side': 'left',
          'role': 'line',
        }
      ],
    });

    expect(ve.hasChassisSvg, isTrue);
    expect(ve.chassisSvg, contains('<svg'));
    expect(ve.svgFallback, isFalse);
    expect(ve.chrome?.hasSoftKeys, isTrue);
    expect(ve.chrome?.navCluster?.width, 72);
    expect(ve.softKeys, hasLength(1));
    expect(ve.softKeys.first.label, 'Menu');
    expect(ve.keys.first.role, 'line');
  });

  test('TemplateMetadataParser reads visual_editor from META comment', () {
    const source = '''
{{! META: {
  "manufacturer": "Test",
  "model_family": "X",
  "display_name": "Test Phone",
  "config_format": "cfg",
  "content_type": "text/plain",
  "filename_pattern": "{mac}.cfg",
  "supported_models": ["T54W"],
  "max_line_keys": 10,
  "categories": [],
  "variables": [],
  "visual_editor": {
    "svg_fallback": false,
    "chassis_svg_b64": "PHN2Zz48L3N2Zz4=",
    "schematic": {
      "chassis_width": 340,
      "chassis_height": 560,
      "screen_x": 58,
      "screen_y": 42,
      "screen_width": 224,
      "screen_height": 168
    },
    "keys_per_page": 10,
    "chrome": {"has_soft_keys": true, "has_nav_cluster": true, "has_dial_pad": true},
    "soft_keys": [{"label": "Dir", "x": 10, "y": 20, "width": 40, "height": 18}],
    "keys": [{"index": 1, "x": 12, "y": 52, "width": 42, "height": 22, "page": 1, "side": "left"}]
  }
} }}
# body
''';
    final meta = TemplateMetadataParser.parseSource(source);
    expect(meta.displayName, 'Test Phone');
    expect(meta.visualEditor, isNotNull);
    expect(meta.visualEditor!.hasChassisSvg, isTrue);
    expect(meta.visualEditor!.softKeys.first.label, 'Dir');
  });
}
