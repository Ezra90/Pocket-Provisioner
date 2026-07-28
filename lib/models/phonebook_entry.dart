import 'dart:convert';

/// A single contact entry in a per-device phonebook.
class PhonebookEntry {
  String name;
  String phone;
  String group; // Display group / category label (optional, default 'All Contacts')
  /// Polycom local-directory speed-dial index (VVX1500 home-screen hotkeys).
  int? speedDialIndex;
  /// Polycom buddy-watch / presence for BLF-style directory entries.
  bool buddyWatch;

  PhonebookEntry({
    required this.name,
    required this.phone,
    this.group = 'All Contacts',
    this.speedDialIndex,
    this.buddyWatch = false,
  });

  PhonebookEntry clone() => PhonebookEntry(
        name: name,
        phone: phone,
        group: group,
        speedDialIndex: speedDialIndex,
        buddyWatch: buddyWatch,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'group': group,
        if (speedDialIndex != null) 'sd': speedDialIndex,
        if (buddyWatch) 'bw': 1,
      };

  factory PhonebookEntry.fromJson(Map<String, dynamic> m) => PhonebookEntry(
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? m['number'] as String? ?? '',
        group: m['group'] as String? ?? 'All Contacts',
        speedDialIndex: m['sd'] is int
            ? m['sd'] as int
            : int.tryParse('${m['sd'] ?? ''}'),
        buddyWatch: m['bw'] == true ||
            m['bw'] == 1 ||
            m['bw'] == '1' ||
            m['buddyWatch'] == true,
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
