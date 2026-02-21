import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/device.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('provisioner_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 3,
      onCreate: (db, version) async {
      // 1. Devices Table
      await db.execute('''
        CREATE TABLE devices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          model TEXT NOT NULL,
          extension TEXT UNIQUE NOT NULL,
          secret TEXT NOT NULL,
          label TEXT NOT NULL,
          mac_address TEXT,
          status TEXT DEFAULT 'PENDING'
        )
      ''');

      // 2. Templates Table
      await db.execute('''
        CREATE TABLE templates (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          model_name TEXT UNIQUE NOT NULL,
          content_type TEXT NOT NULL,
          content TEXT NOT NULL
        )
      ''');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        // Future migrations go here
        // Example: await db.execute('ALTER TABLE devices ADD COLUMN firmware_version TEXT');
      }
      if (oldVersion < 3) {
        // Recreate devices table with UNIQUE constraint on extension
        await db.execute('''
          CREATE TABLE devices_tmp (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model TEXT NOT NULL,
            extension TEXT UNIQUE NOT NULL,
            secret TEXT NOT NULL,
            label TEXT NOT NULL,
            mac_address TEXT,
            status TEXT DEFAULT 'PENDING'
          )
        ''');
        await db.execute('''
          INSERT OR REPLACE INTO devices_tmp (id, model, extension, secret, label, mac_address, status)
          SELECT id, model, extension, secret, label, mac_address, status FROM devices
        ''');
        await db.execute('DROP TABLE devices');
        await db.execute('ALTER TABLE devices_tmp RENAME TO devices');
      }
    },
    );
  }

  /// Raw SQL UPSERT statement used by both insertDevice and insertDevices.
  /// On an extension conflict it:
  ///  - always takes the new model, secret, and label
  ///  - keeps the existing mac_address when one is already stored
  ///  - keeps the existing status   when a mac_address is already stored
  static const String _upsertDeviceSql = '''
    INSERT INTO devices (model, extension, secret, label, mac_address, status)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(extension) DO UPDATE SET
      model     = excluded.model,
      secret    = excluded.secret,
      label     = excluded.label,
      mac_address = COALESCE(devices.mac_address, excluded.mac_address),
      status    = CASE
                    WHEN devices.mac_address IS NOT NULL THEN devices.status
                    ELSE excluded.status
                  END
  ''';

  // --- Device Methods ---
  Future<void> insertDevice(Device device) async {
    final db = await instance.database;
    await db.rawInsert(_upsertDeviceSql, [
      device.model,
      device.extension,
      device.secret,
      device.label,
      device.macAddress,
      device.status,
    ]);
  }

  Future<Device?> getNextPendingDevice() async {
    final db = await instance.database;
    final maps = await db.query('devices', where: 'mac_address IS NULL', orderBy: 'extension ASC', limit: 1);
    if (maps.isNotEmpty) return Device.fromMap(maps.first);
    return null;
  }

  Future<int> getPendingCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM devices WHERE mac_address IS NULL');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> assignMac(int id, String mac) async {
    final db = await instance.database;
    await db.update('devices', {'mac_address': mac, 'status': 'READY'}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Device?> getDeviceByMac(String mac) async {
    final db = await instance.database;
    final maps = await db.query('devices', where: 'mac_address = ?', whereArgs: [mac]);
    if (maps.isNotEmpty) return Device.fromMap(maps.first);
    return null;
  }

  // --- Template Methods ---
  Future<void> saveTemplate(String model, String type, String content) async {
    final db = await instance.database;
    await db.insert(
      'templates', 
      {'model_name': model, 'content_type': type, 'content': content},
      conflictAlgorithm: ConflictAlgorithm.replace
    );
  }

  Future<Map<String, dynamic>?> getTemplate(String model) async {
    final db = await instance.database;
    final maps = await db.query('templates', where: 'model_name = ?', whereArgs: [model]);
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> clearDevices() async {
    final db = await instance.database;
    await db.delete('devices');
  }

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('devices');
    await db.delete('templates');
  }

  Future<List<Device>> getReadyDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: 'status = ? AND mac_address IS NOT NULL',
      whereArgs: ['READY'],
    );
    return List.generate(maps.length, (i) => Device.fromMap(maps[i]));
  }

  /// Retrieve all devices (for label lookup and auto-sequential BLF)
  Future<List<Device>> getAllDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('devices');
    return List.generate(maps.length, (i) => Device.fromMap(maps[i]));
  }

  /// Batch insert devices using a single transaction for performance
  Future<void> insertDevices(List<Device> devices) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final device in devices) {
      batch.rawInsert(_upsertDeviceSql, [
        device.model,
        device.extension,
        device.secret,
        device.label,
        device.macAddress,
        device.status,
      ]);
    }
    await batch.commit(noResult: true);
  }
}