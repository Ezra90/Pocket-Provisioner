/// Represents a single HTTP access event during a provisioning session.
class AccessLogEntry {
  final String clientIp;
  final String requestedPath;
  final String? resolvedMac;
  final String? deviceLabel;
  final String? deviceExtension;
  final String resourceType;
  final int statusCode;
  final DateTime timestamp;

  AccessLogEntry({
    required this.clientIp,
    required this.requestedPath,
    this.resolvedMac,
    this.deviceLabel,
    this.deviceExtension,
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

  /// Returns a user-friendly resource type label for display.
  String get resourceTypeLabel {
    switch (resourceType) {
      case 'config':
        return 'Config';
      case 'wallpaper':
        return 'Wallpaper';
      case 'ringtone':
        return 'Ringtone';
      case 'phonebook':
        return 'Phonebook';
      case 'firmware':
        return 'Firmware';
      default:
        return resourceType;
    }
  }

  /// Returns a formatted summary string for toast notifications.
  /// Format: "fetched Config | Ext 101 | Reception | 192.168.1.100"
  String get toastSummary {
    final parts = <String>[];
    
    // Add what was accessed
    parts.add('fetched $resourceTypeLabel');
    
    // Add device identification info (in order of specificity)
    if (deviceExtension != null) {
      parts.add('Ext $deviceExtension');
    }
    if (deviceLabel != null && deviceLabel!.isNotEmpty) {
      parts.add(deviceLabel!);
    }
    if (resolvedMac != null) {
      parts.add(formattedMac);
    }
    
    // Always include IP
    parts.add(clientIp);
    
    return parts.join(' | ');
  }

  /// Returns a detailed summary showing all available device info and the path accessed.
  /// Format: "IP: 192.168.1.100 | MAC: AA:BB:.. | Ext 101 | Label | Path: /file.cfg"
  String get detailedSummary {
    final parts = <String>[];
    
    parts.add('IP: $clientIp');
    if (resolvedMac != null) {
      parts.add('MAC: $formattedMac');
    }
    if (deviceExtension != null) {
      parts.add('Ext: $deviceExtension');
    }
    if (deviceLabel != null && deviceLabel!.isNotEmpty) {
      parts.add('Name: $deviceLabel');
    }
    parts.add('File: $requestedPath');
    
    return parts.join(' | ');
  }
}
