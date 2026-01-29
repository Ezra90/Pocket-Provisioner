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

    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      // 1. Devices Table
      await db.execute('''
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

      // 2. Templates Table
      await db.execute('''
        CREATE TABLE templates (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          model_name TEXT UNIQUE NOT NULL,
          content_type TEXT NOT NULL,
          content TEXT NOT NULL
        )
      ''');
    });
  }

  // --- Device Methods ---
  Future<void> insertDevice(Device device) async {
    final db = await instance.database;
    await db.insert('devices', device.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Device?> getNextPendingDevice() async {
    final db = await instance.database;
    final maps = await db.query('devices', where: 'mac_address IS NULL', orderBy: 'extension ASC', limit: 1);
    if (maps.isNotEmpty) return Device.fromMap(maps.first);
    return null;
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

  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('devices');
  }
/// NEW METHOD: Retrieve all devices (for label lookup and auto-sequential BLF)
Future<List<Device>> getAllDevices() async {
  final db = await database;
  final List<Map<String, dynamic>> maps = await db.query('devices');
  
  return List.generate(maps.length, (i) {
    return Device.fromMap(maps[i]);
  });
}
