/// Represents a single VoIP Handset to be deployed.
class Device {
  final int? id;
  final String model;      // e.g., "T58G", "VVX411"
  final String extension;  // e.g., "101"
  final String secret;     // SIP Password
  final String label;      // Screen Name (e.g. "Reception")
  final String? macAddress;// The scanned physical address
  final String status;     // PENDING, READY, PROVISIONED

  Device({
    this.id,
    required this.model,
    required this.extension,
    required this.secret,
    required this.label,
    this.macAddress,
    this.status = 'PENDING',
  });

  // Convert Device object to Map for SQL
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'model': model,
      'extension': extension,
      'secret': secret,
      'label': label,
      'mac_address': macAddress,
      'status': status,
    };
  }

  // Extract Device object from SQL Map
  factory Device.fromMap(Map<String, dynamic> map) {
    return Device(
      id: map['id'],
      model: map['model'],
      extension: map['extension'],
      secret: map['secret'],
      label: map['label'],
      macAddress: map['mac_address'],
      status: map['status'],
    );
  }
}
