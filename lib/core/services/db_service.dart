import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../models/punch.dart';

/// Encrypted local store (SQLCipher). The key is random, created on first run and kept in
/// the platform secure storage. Every punch is written here first, then synced.
class DbService {
  static Database? _db;
  static const _s = FlutterSecureStorage(
    // Keep these items on this phone only. The iOS default can be restored onto a new phone
    // from a backup, which would copy the device binding ID and the database key with it.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static Future<String> _key() async {
    var k = await _s.read(key: 'dbKey');
    if (k == null) {
      final r = Random.secure();
      k = base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256)));
      await _s.write(key: 'dbKey', value: k);
    }
    return k;
  }

  static Future<Database> get _d async => _db ??= await openDatabase(
        join(await getDatabasesPath(), 'attendance_enc.db'),
        password: await _key(),
        version: 1,
        onCreate: (db, v) => db.execute('''
          CREATE TABLE punches(
            id TEXT PRIMARY KEY, type TEXT, lat REAL, lng REAL, accuracy REAL,
            site_id TEXT, device_id TEXT, client_time TEXT,
            synced INTEGER DEFAULT 0,
            selfie_path TEXT, has_selfie INTEGER DEFAULT 0, selfie_synced INTEGER DEFAULT 0,
            device_flags TEXT)'''),
      );

  static const _pendingWhere =
      'synced = 0 OR (selfie_path IS NOT NULL AND selfie_synced = 0)';

  static Future<void> insert(Punch p) async =>
      (await _d).insert('punches', p.toMap());

  /// Punches that still need the punch itself or its selfie uploaded.
  static Future<List<Punch>> pending() async {
    final r = await (await _d)
        .query('punches', where: _pendingWhere, orderBy: 'client_time ASC');
    return r.map(Punch.fromMap).toList();
  }

  static Future<int> pendingCount() async {
    final r = await (await _d)
        .rawQuery('SELECT COUNT(*) c FROM punches WHERE $_pendingWhere');
    return (r.first['c'] as int?) ?? 0;
  }

  static Future<void> markSynced(String id) async => (await _d)
      .update('punches', {'synced': 1}, where: 'id = ?', whereArgs: [id]);

  static Future<void> markSelfieSynced(String id) async => (await _d).update(
      'punches', {'selfie_synced': 1, 'selfie_path': null},
      where: 'id = ?', whereArgs: [id]);

  /// Newest first.
  static Future<List<Punch>> recent({int limit = 30}) async {
    final r = await (await _d)
        .query('punches', orderBy: 'client_time DESC', limit: limit);
    return r.map(Punch.fromMap).toList();
  }

  /// Oldest first, from [sinceUtc] onwards.
  static Future<List<Punch>> since(DateTime sinceUtc) async {
    final r = await (await _d).query('punches',
        where: 'client_time >= ?',
        whereArgs: [sinceUtc.toUtc().toIso8601String()],
        orderBy: 'client_time ASC');
    return r.map(Punch.fromMap).toList();
  }
}
