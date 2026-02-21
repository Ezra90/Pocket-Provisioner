class ButtonKey {
  final int id;
  String type; // 'none', 'blf', 'speeddial', 'line', etc.
  String value; // effective value used in config (may be shortened)
  String label; // custom label (optional — auto-filled from device label for BLF)
  String fullValue; // original full extension / phone number (before any shortening)
  String shortDialMode; // 'full', '3digit', '4digit', '5digit', 'custom'
  int customDigits; // trailing digits to keep when shortDialMode == 'custom'

  ButtonKey(
    this.id, {
    this.type = 'none',
    this.value = '',
    this.label = '',
    this.fullValue = '',
    this.shortDialMode = 'full',
    this.customDigits = 3,
  });

  /// Recomputes [value] from [fullValue] according to [shortDialMode].
  /// Call this whenever [fullValue] or [shortDialMode] changes.
  void applyShortDial() {
    if (fullValue.isEmpty) return;
    final int digits = switch (shortDialMode) {
      '3digit' => 3,
      '4digit' => 4,
      '5digit' => 5,
      'custom' => customDigits,
      _ => 0, // 'full' — no shortening
    };
    if (digits == 0) {
      value = fullValue;
    } else {
      value = fullValue.length > digits
          ? fullValue.substring(fullValue.length - digits)
          : fullValue;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'value': value,
        'label': label,
        'fullValue': fullValue,
        'shortDialMode': shortDialMode,
        'customDigits': customDigits,
      };

  factory ButtonKey.fromJson(Map<String, dynamic> json) => ButtonKey(
        json['id'] as int,
        type: json['type'] as String? ?? 'none',
        value: json['value'] as String? ?? '',
        label: json['label'] as String? ?? '',
        fullValue: json['fullValue'] as String? ?? '',
        shortDialMode: json['shortDialMode'] as String? ?? 'full',
        customDigits: json['customDigits'] as int? ?? 3,
      );

  /// Returns a shallow copy of this key with all fields duplicated.
  ButtonKey clone() => ButtonKey(
        id,
        type: type,
        value: value,
        label: label,
        fullValue: fullValue,
        shortDialMode: shortDialMode,
        customDigits: customDigits,
      );

  @override
  String toString() {
    return 'Key $id: $type - $value ($label)';
  }
}
