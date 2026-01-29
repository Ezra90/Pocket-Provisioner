import 'dart:convert';

class ButtonKey {
  final int id;
  String type; // 'none', 'blf', 'speeddial', 'line', etc.
  String value; // extension or phone number
  String label; // custom label (optional — auto-filled from device label for BLF)

  ButtonKey(
    this.id, {
    this.type = 'none',
    this.value = '',
    this.label = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'value': value,
        'label': label,
      };

  factory ButtonKey.fromJson(Map<String, dynamic> json) => ButtonKey(
        json['id'] as int,
        type: json['type'] as String? ?? 'none',
        value: json['value'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );

  @override
  String toString() {
    return 'Key $id: $type - $value ($label)';
  }
}
