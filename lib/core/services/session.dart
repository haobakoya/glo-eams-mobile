import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Holds login state and the device binding ID in encrypted storage.
class Session {
  static const _s = FlutterSecureStorage(
    // Keep these items on this phone only. The iOS default can be restored onto a new phone
    // from a backup, which would copy the device binding ID and the database key with it.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static String? token, name, staffId, staffType; // staffType: regular|shift|field
  static bool isManager = false, faceEnrolled = false;
  static String faceStatus = 'none'; // none | pending | confirmed (by the manager)
  static String deviceId = '';

  static bool get loggedIn => token != null && token!.isNotEmpty;

  static Future<void> load() async {
    token = await _s.read(key: 'token');
    name = await _s.read(key: 'name');
    staffId = await _s.read(key: 'staffId');
    staffType = await _s.read(key: 'staffType');
    isManager = await _s.read(key: 'isManager') == '1';
    faceEnrolled = await _s.read(key: 'faceEnrolled') == '1';
    faceStatus = await _s.read(key: 'faceStatus') ?? 'none';
    var id = await _s.read(key: 'deviceId');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _s.write(key: 'deviceId', value: id);
    }
    deviceId = id;
  }

  static Future<void> save({
    required String token,
    required String name,
    required String staffId,
    required String staffType,
    bool isManager = false,
    bool faceEnrolled = false,
    String faceStatus = 'none',
  }) async {
    Session.token = token;
    Session.name = name;
    Session.staffId = staffId;
    Session.staffType = staffType;
    Session.isManager = isManager;
    Session.faceEnrolled = faceEnrolled;
    Session.faceStatus = faceStatus;
    await _s.write(key: 'token', value: token);
    await _s.write(key: 'name', value: name);
    await _s.write(key: 'staffId', value: staffId);
    await _s.write(key: 'staffType', value: staffType);
    await _s.write(key: 'isManager', value: isManager ? '1' : '0');
    await _s.write(key: 'faceEnrolled', value: faceEnrolled ? '1' : '0');
    await _s.write(key: 'faceStatus', value: faceStatus);
  }

  static Future<void> setFaceEnrolled(bool v) async {
    faceEnrolled = v;
    await _s.write(key: 'faceEnrolled', value: v ? '1' : '0');
  }

  static Future<void> setFaceStatus(String v) async {
    faceStatus = v;
    await _s.write(key: 'faceStatus', value: v);
  }

  static Future<void> clear() async {
    token = name = staffId = staffType = null;
    isManager = faceEnrolled = false;
    faceStatus = 'none';
    for (final k in [
      'token', 'name', 'staffId', 'staffType', 'isManager', 'faceEnrolled', 'faceStatus',
      'sites', 'shifts', 'selfieNoticeOk'
    ]) {
      await _s.delete(key: k);
    }
  }

  static Future<String?> readRaw(String key) => _s.read(key: key);
  static Future<void> writeRaw(String key, String value) =>
      _s.write(key: key, value: value);
}
