/*import 'dart:convert';
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
*/
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/punch.dart';

/// Encrypted local store (SQLCipher). The key is random, created on first run and kept in
/// the platform secure storage. Every punch is written here first, then synced.
///
/// Self-healing: if the database file and its key ever get out of step (key lost, secure
/// storage changed between builds, file restored from a backup without its key), the old
/// file can never be decrypted. Instead of failing on every read forever, the unreadable
/// file is set aside (renamed to *.unreadable) and a fresh database is created. The server
/// remains the record of synced punches; see [mergeRemote] for pulling them back in.
class DbService {
  static Database? _db;
  static Future<Database>? _opening;

  /// True when this run found the old local database unreadable and started an empty one.
  /// The app can use this to pull the last days of punches back from the server.
  static bool resetThisRun = false;

  static const _dbName = 'attendance_enc.db';

  static const _s = FlutterSecureStorage(
    // Keep these items on this phone only. The iOS default can be restored onto a new phone
    // from a backup, which would copy the device binding ID and the database key with it.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // ---------------------------------------------------------------------------
  // Key handling
  // ---------------------------------------------------------------------------

  static String _newKey() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  static Future<String> _key() async {
    var k = await _s.read(key: 'dbKey');
    if (k == null) {
      k = _newKey();
      await _s.write(key: 'dbKey', value: k);
    }
    return k;
  }

  /// Used only when the stored key cannot be read at all.
  /// Deletes just the dbKey entry (not the rest of secure storage, which also holds
  /// other items such as the device binding ID).
  static Future<String> _replaceKey() async {
    try {
      await _s.delete(key: 'dbKey');
    } catch (e) {
      debugPrint('DB: could not delete the old key entry: $e');
    }
    final k = _newKey();
    await _s.write(key: 'dbKey', value: k);
    return k;
  }

  // ---------------------------------------------------------------------------
  // Opening
  // ---------------------------------------------------------------------------

  static bool _looksUnreadable(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('not a database') ||
        m.contains('file is encrypted') ||
        m.contains('notadb');
  }

  /// Sets the database files aside so a fresh one can be created.
  /// Renamed, not deleted, in case the key is ever recovered.
  static Future<void> _quarantine(String path) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      try {
        if (await f.exists()) {
          await f.rename('$path$suffix.unreadable');
        }
      } catch (_) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  static Future<Database> _openAt(String path, String key) async {
    final db = await openDatabase(
      path,
      password: key,
      // To change the schema later: raise the version and add an onUpgrade that
      // runs ALTER TABLE ... ADD COLUMN for the new column(s).
      version: 1,
      onCreate: (db, v) => db.execute('''
        CREATE TABLE punches(
          id TEXT PRIMARY KEY, type TEXT, lat REAL, lng REAL, accuracy REAL,
          site_id TEXT, device_id TEXT, client_time TEXT,
          synced INTEGER DEFAULT 0,
          selfie_path TEXT, has_selfie INTEGER DEFAULT 0, selfie_synced INTEGER DEFAULT 0,
          device_flags TEXT)'''),
    );

    // Prove the file really decrypts and the table is readable now, not on first use.
    try {
      await db.rawQuery('SELECT 1 FROM punches LIMIT 1');
    } catch (e) {
      await db.close();
      rethrow;
    }
    return db;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);

    String key;
    try {
      key = await _key();
    } catch (e, st) {
      // The stored key cannot be read (for example the Android keystore entry was lost).
      // The existing file can never be opened without it.
      debugPrint('DB: key could not be read: $e');
      debugPrintStack(stackTrace: st);
      await _quarantine(path);
      key = await _replaceKey();
      resetThisRun = true;
      return _openAt(path, key);
    }

    try {
      return await _openAt(path, key);
    } catch (e, st) {
      if (!_looksUnreadable(e)) rethrow; // other errors are real bugs: surface them
      debugPrint('DB: file cannot be decrypted with the stored key, starting a new one: $e');
      debugPrintStack(stackTrace: st);
      await _quarantine(path);
      resetThisRun = true;
      return _openAt(path, key);
    }
  }

  static Future<Database> _openGuarded() async {
    try {
      return _db = await _open();
    } finally {
      _opening = null;
    }
  }

  static Future<Database> get _d {
    final db = _db;
    if (db != null) return Future.value(db);
    // Concurrent callers share one open attempt.
    return _opening ??= _openGuarded();
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

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

  /// Adds punches that already exist on the server (for example after a reinstall).
  ///
  /// Each row must use the table's column names: id, type, lat, lng, accuracy, site_id,
  /// device_id, client_time (UTC ISO-8601, same format as local punches), and optionally
  /// has_selfie. Rows whose id is already stored are skipped, so local data is never
  /// overwritten. Merged rows are marked as already synced.
  static Future<void> mergeRemote(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final batch = (await _d).batch();
    for (final r in rows) {
      batch.insert(
        'punches',
        {
          ...r,
          'synced': 1,
          'selfie_synced': 1,
          'selfie_path': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }
}