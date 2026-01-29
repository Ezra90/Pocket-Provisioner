import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/device.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('provisioner_v1.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: (db, version) {
      return db.execute('''
        CREATE TABLE devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          model TEXT NOT NULL,
          extension TEXT NOT NULL,
          secret TEXT NOT NULL,
          label TEXT NOT NULL,
          mac_address TEXT,
          status TEXT DEFAULT 'PENDING'
        )
      ''');
    });
  }

  /// Insert a single device (from CSV import)
  Future<void> insertDevice(Device device) async {
    final db = await instance.database;
    await db.insert('devices', device.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get the next device in the queue that has NO Mac Address
  Future<Device?> getNextPendingDevice() async {
    final db = await instance.database;
    final maps = await db.query(
      'devices',
      where: 'mac_address IS NULL',
      orderBy: 'extension ASC',
      limit: 1,
    );
    if (maps.isNotEmpty) return Device.fromMap(maps.first);
    return null;
  }

  /// Update the MAC address for a specific ID
  Future<void> assignMac(int id, String mac) async {
    final db = await instance.database;
    await db.update(
      'devices',
      {'mac_address': mac, 'status': 'READY'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retrieve a device by MAC (used by the Web Server)
  Future<Device?> getDeviceByMac(String mac) async {
    final db = await instance.database;
    final maps = await db.query(
      'devices',
      where: 'mac_address = ?',
      whereArgs: [mac],
    );
    if (maps.isNotEmpty) return Device.fromMap(maps.first);
    return null;
  }

  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('devices');
  }
}
