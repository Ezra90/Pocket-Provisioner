import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_provisioner/models/button_key.dart';
import 'package:pocket_provisioner/services/mustache_renderer.dart';

void main() {
  test('buildVariables uses 1-based button id as linekey position', () {
    final vars = MustacheRenderer.buildVariables(
      macAddress: 'AABBCCDDEEFF',
      extension: '101',
      displayName: 'Desk',
      secret: 'secret',
      model: 'T54W',
      sipServer: '192.168.1.1',
      provisioningUrl: 'http://192.168.1.2/',
      lineKeys: [
        ButtonKey(1, type: 'line', value: '101', label: 'Line'),
        ButtonKey(2, type: 'blf', value: '102', label: 'Bob'),
      ],
    );

    final lineKeys = vars['line_keys'] as List<Map<String, dynamic>>;
    expect(lineKeys, hasLength(2));
    expect(lineKeys[0]['position'], 1);
    expect(lineKeys[1]['position'], 2);

    expect(vars['provisioning_base'], 'http://192.168.1.2/');
    expect(vars['provisioning_url'], 'http://192.168.1.2/');

    final attendant = vars['attendant_keys'] as List<Map<String, dynamic>>;
    expect(attendant.single['position'], 2);
  });
}
