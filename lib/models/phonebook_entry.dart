import 'dart:convert';

/// A single contact entry in a per-device phonebook.
class PhonebookEntry {
  String name;
  String phone;
  String group; // Display group / category label (optional, default 'All Contacts')

  PhonebookEntry({
    required this.name,
    required this.phone,
    this.group = 'All Contacts',
  });

  PhonebookEntry clone() =>
      PhonebookEntry(name: name, phone: phone, group: group);

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'group': group,
      };

  factory PhonebookEntry.fromJson(Map<String, dynamic> m) => PhonebookEntry(
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        group: m['group'] as String? ?? 'All Contacts',
      );

  /// Encode a list of entries to a JSON string for DB storage.
  static String encodeList(List<PhonebookEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  /// Decode a list of entries from a JSON string; returns empty list on failure.
  static List<PhonebookEntry> decodeList(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List<dynamic>;
      return list
          .map((e) => PhonebookEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
