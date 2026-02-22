import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/device.dart';
import '../models/device_settings.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  Database? _database;
  Future<Database>? _dbInitFuture;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _dbInitFuture ??= _initDB('provisioner_v2.db');
    _database = await _dbInitFuture!;
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 5,
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
          status TEXT DEFAULT 'PENDING',
          wallpaper TEXT,
          device_settings TEXT
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
      await db.transaction((txn) async {
        if (oldVersion < 3) {
          // Recreate devices table with UNIQUE constraint on extension
          await txn.execute('''
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
          await txn.execute('''
            INSERT OR REPLACE INTO devices_tmp (id, model, extension, secret, label, mac_address, status)
            SELECT id, model, extension, secret, label, mac_address, status FROM devices
          ''');
          await txn.execute('DROP TABLE devices');
          await txn.execute('ALTER TABLE devices_tmp RENAME TO devices');
        }
        if (oldVersion < 4) {
          await txn.execute('ALTER TABLE devices ADD COLUMN wallpaper TEXT');
        }
        if (oldVersion < 5) {
          await txn.execute('ALTER TABLE devices ADD COLUMN device_settings TEXT');
        }
      });
    },
    );
  }

  // --- Device Methods ---
  Future<void> insertDevice(Device device) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      List<Map<String, dynamic>> existing = [];
      if (device.id != null) {
        existing = await txn.query(
          'devices',
          where: 'id = ?',
          whereArgs: [device.id],
        );
      } else {
        existing = await txn.query(
          'devices',
          where: 'extension = ?',
          whereArgs: [device.extension],
        );
      }

      if (existing.isNotEmpty) {
        final existingDevice = Device.fromMap(existing.first);
        await txn.update(
          'devices',
          {
            'model': device.model,
            'extension': device.extension,
            'secret': device.secret,
            'label': device.label,
            'mac_address': existingDevice.macAddress ?? device.macAddress,
            'status': existingDevice.macAddress != null ? existingDevice.status : device.status,
            'wallpaper': device.wallpaper,
            'device_settings': device.deviceSettings?.toJsonString(),
          },
          where: 'id = ?',
          whereArgs: [existingDevice.id],
        );
      } else {
        await txn.insert('devices', device.toMap());
      }
    });
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
    await db.update('devices', {'mac_address': mac.toUpperCase(), 'status': 'READY'}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Device?> getDeviceByMac(String mac) async {
    final db = await instance.database;
    final maps = await db.query('devices', where: 'mac_address = ?', whereArgs: [mac]);
    if (maps.isNotEmpty) return Device.fromMap(maps.first);
    return null;
  }

  // --- Template Methods ---

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

  /// Retrieve all PENDING devices (no MAC assigned) ordered by extension.
  Future<List<Device>> getPendingDevices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'devices',
      where: 'mac_address IS NULL',
      orderBy: 'extension ASC',
    );
    return List.generate(maps.length, (i) => Device.fromMap(maps[i]));
  }

  /// Update the model for a single device.
  Future<void> updateDeviceModel(int id, String model) async {
    final db = await instance.database;
    await db.update('devices', {'model': model}, where: 'id = ?', whereArgs: [id]);
  }

  /// Updates per-device settings and optionally the wallpaper for a device.
  /// [wallpaper] null = keep existing; non-null = replace (pass '' to clear).
  Future<void> updateDeviceSettings(
      int id, DeviceSettings? settings, String? wallpaper) async {
    final db = await instance.database;
    final fields = <String, dynamic>{
      'device_settings': settings?.toJsonString(),
    };
    if (wallpaper != null) fields['wallpaper'] = wallpaper.isEmpty ? null : wallpaper;
    await db.update('devices', fields, where: 'id = ?', whereArgs: [id]);
  }

  /// Updates the MAC address and status for a single device.
  Future<void> updateDeviceMac(int id, String mac) async {
    final db = await instance.database;
    await db.update(
      'devices',
      {'mac_address': mac.toUpperCase(), 'status': 'READY'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a single device by ID.
  Future<void> deleteDevice(int id) async {
    final db = await instance.database;
    await db.delete('devices', where: 'id = ?', whereArgs: [id]);
  }

  /// Batch insert devices using a single transaction for performance
  Future<void> insertDevices(List<Device> devices) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();

      // Pull all existing devices into a map for O(1) in-memory lookups
      final List<Map<String, dynamic>> existingMaps = await txn.query('devices');
      final existingByExtension = <String, Device>{
        for (final m in existingMaps) (m['extension'] as String): Device.fromMap(m),
      };

      for (final device in devices) {
        final existingDevice = existingByExtension[device.extension];

        if (existingDevice != null) {
          batch.update(
            'devices',
            {
              'model': device.model,
              'secret': device.secret,
              'label': device.label,
              'mac_address': existingDevice.macAddress ?? device.macAddress,
              'status': existingDevice.macAddress != null ? existingDevice.status : device.status,
              'wallpaper': device.wallpaper,
              'device_settings': device.deviceSettings?.toJsonString(),
            },
            where: 'extension = ?',
            whereArgs: [device.extension],
          );
        } else {
          batch.insert('devices', device.toMap());
        }
      }

      await batch.commit(noResult: true);
    });
  }
}