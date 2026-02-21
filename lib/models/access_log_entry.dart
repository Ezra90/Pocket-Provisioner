/// Represents a single HTTP access event during a provisioning session.
class AccessLogEntry {
  final String clientIp;
  final String requestedPath;
  final String? resolvedMac;
  final String? deviceLabel;
  final String resourceType;
  final int statusCode;
  final DateTime timestamp;

  AccessLogEntry({
    required this.clientIp,
    required this.requestedPath,
    this.resolvedMac,
    this.deviceLabel,
    required this.resourceType,
    required this.statusCode,
    required this.timestamp,
  });

  /// Format MAC address with colons (e.g. AABBCCDDEEFF → AA:BB:CC:DD:EE:FF)
  String get formattedMac {
    if (resolvedMac == null || resolvedMac!.length != 12) return resolvedMac ?? '';
    final m = resolvedMac!.toUpperCase();
    return '${m.substring(0, 2)}:${m.substring(2, 4)}:${m.substring(4, 6)}:'
        '${m.substring(6, 8)}:${m.substring(8, 10)}:${m.substring(10, 12)}';
  }
}
