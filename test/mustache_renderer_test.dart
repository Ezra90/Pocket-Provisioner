import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_provisioner/models/button_key.dart';
import 'package:pocket_provisioner/models/phonebook_entry.dart';
import 'package:pocket_provisioner/services/mustache_renderer.dart';
import 'package:pocket_provisioner/services/phonebook_service.dart';

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
    // Poly resourceList indexes are sequential starting at 1
    expect(attendant.single['position'], 1);
    expect(attendant.single['key_value'], '102');
  });

  test('VVX1500 auto video/TCP and skips FLK; keeps speedDial + attendant', () {
    final vars = MustacheRenderer.buildVariables(
      macAddress: '0004F24DA209',
      extension: '101',
      displayName: 'Front Desk',
      secret: 'secret',
      model: 'VVX1500',
      sipServer: 'pbx.example.com',
      provisioningUrl: 'http://pbx.example.com/prov/',
      lineKeys: [
        ButtonKey(1, type: 'line', value: '101', label: 'Front Desk'),
        // UI stores type as "speeddial" (no underscore)
        ButtonKey(2, type: 'speeddial', value: '104', label: 'Bill Botel'),
        ButtonKey(3, type: 'blf', value: '104', label: 'Bill Botel'),
      ],
      polycomContactsDirectory: 'http://pbx.example.com/prov/',
      phonebookUrl: 'http://pbx.example.com/prov/0004f24da209-directory.xml',
    );

    expect(vars['poly_two_column_display'], isTrue);
    expect(vars['has_speed_dial_keys'], isTrue);
    expect(vars['has_attendant_keys'], isTrue);
    expect(vars['video_enable'], '1');
    expect(vars['video_auto_start'], '1');
    expect(vars['sip_transport_mode'], 'TCPPreferred');
    expect(vars['has_poly_line_key_assignments'], isFalse);
    expect(vars['poly_line_key_assignments'], isEmpty);
    expect(vars['has_polycom_contacts_directory'], isTrue);

    final speed = vars['speed_dial_keys'] as List<Map<String, dynamic>>;
    expect(speed.single['position'], 1);
    expect(speed.single['key_value'], '104');
  });

  test('non-VVX Poly still emits FLK assignments', () {
    final vars = MustacheRenderer.buildVariables(
      macAddress: '0004F24DA209',
      extension: '101',
      displayName: 'Desk',
      secret: 'secret',
      model: 'VVX450',
      sipServer: 'pbx.example.com',
      provisioningUrl: 'http://pbx.example.com/prov/',
      lineKeys: [
        ButtonKey(1, type: 'line', value: '101', label: 'Line'),
        ButtonKey(2, type: 'speed_dial', value: '104', label: 'Bill'),
        ButtonKey(3, type: 'blf', value: '104', label: 'Bill'),
      ],
    );

    expect(vars['video_enable'], '0');
    expect(vars['sip_transport_mode'], 'UDPOnly');
    expect(vars['has_poly_line_key_assignments'], isTrue);
    final poly = vars['poly_line_key_assignments'] as List<Map<String, dynamic>>;
    expect(poly.map((e) => e['category']).toList(), ['Line', 'SpeedDial', 'BLF']);
  });

  test('default dial plan is 3-digit hotel friendly', () {
    final vars = MustacheRenderer.buildVariables(
      macAddress: 'AABBCCDDEEFF',
      extension: '101',
      displayName: 'Desk',
      secret: 'secret',
      model: 'VVX1500',
      sipServer: 'pbx.example.com',
      provisioningUrl: 'http://pbx.example.com/',
    );
    expect(vars['dial_plan'], '[1-9]xx|*xx.|*x.T|911|0T');
    expect(vars['has_dial_plan'], isTrue);
  });

  test('Poly directory XML gets <sd>/<bw> from button keys', () {
    final contacts = PhonebookService.applyPolyDirectorySpeedDials(
      contacts: const [],
      lineKeys: [
        ButtonKey(1, type: 'line', value: '101', label: 'Hill'),
        ButtonKey(2, type: 'speeddial', value: '104', label: 'Bill Botel'),
        ButtonKey(3, type: 'blf', value: '104', label: 'Bill Botel'),
      ],
      extension: '101',
    );
    expect(contacts, hasLength(1));
    expect(contacts.single.phone, '104');
    expect(contacts.single.speedDialIndex, 1);
    expect(contacts.single.buddyWatch, isTrue);

    final xml = PhonebookService.generatePolycomXml(contacts);
    expect(xml, contains('<sd>1</sd>'));
    expect(xml, contains('<bw>1</bw>'));
    expect(xml, contains('<ct>104</ct>'));
  });

  test('kid_friendly_mode disables web UI and sets is_kid_friendly', () {
    final vars = MustacheRenderer.buildVariables(
      macAddress: 'AABBCCDDEEFF',
      extension: '101',
      displayName: 'Kid Room',
      secret: 'secret',
      model: 'VVX1500',
      sipServer: '192.168.1.1',
      provisioningUrl: 'http://192.168.1.2/',
      kidFriendlyMode: true,
      webUiEnabled: true,
    );
    expect(vars['is_kid_friendly'], isTrue);
    expect(vars['web_ui_enabled'], '0');
    expect(vars['is_web_ui_enabled'], isFalse);
    expect(vars['admin_password'], '789');
    expect(vars['has_admin_password'], isTrue);
  });
}
