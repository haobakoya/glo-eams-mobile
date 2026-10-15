import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/punch.dart';
import '../models/push_result.dart';
import 'api_service.dart';
import 'db_service.dart';
import 'session.dart';

/// Background sync queue: oldest first, stops at the first failure. Punches are idempotent
/// (the server de-duplicates on id). A punch's selfie is uploaded after the punch itself and the
/// local file is deleted once the server has it.
class SyncService {
  static bool _running = false;
  static StreamSubscription? _sub;
  static Timer? _timer;
  static final ValueNotifier<int> pending = ValueNotifier(0);

  static void start() {
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) sync();
    });
    _timer ??= Timer.periodic(AppConfig.syncInterval, (_) => sync());
    sync();
  }

  static void stop() {
    _sub?.cancel();
    _timer?.cancel();
    _sub = null;
    _timer = null;
  }

  static Future<void> updateCount() async =>
      pending.value = await DbService.pendingCount();

  /// Sends one punch (and its selfie). Never throws: if anything fails the result says what did arrive.
  static Future<PushResult> pushOne(Punch p) async {
    var punchOk = p.synced;
    var selfieOk = !(p.selfiePath != null && !p.selfieSynced);
    var flags = <String>[];
    String? face;
    try {
      if (!p.synced) {
        final r = await ApiService.sendPunch(p);
        if (r == null) return PushResult.none;
        await DbService.markSynced(p.id);
        punchOk = true;
        flags = r.flags;
      }
      if (p.selfiePath != null && !p.selfieSynced) {
        final f = File(p.selfiePath!);
        if (await f.exists()) {
          final s = await ApiService.uploadSelfie(p.id, f);
          if (s == null) {
            return PushResult(punchSynced: punchOk, selfieSynced: false, flags: flags);
          }
          face = s.faceStatus;
          try {
            await f.delete();
          } catch (_) {}
        }
        await DbService.markSelfieSynced(p.id);
        selfieOk = true;
      }
    } catch (_) {
      // offline or server down; the queue retries later
    }
    return PushResult(
        punchSynced: punchOk, selfieSynced: selfieOk, flags: flags, faceStatus: face);
  }

  static Future<void> sync() async {
    if (_running || !Session.loggedIn) return;
    _running = true;
    try {
      for (final p in await DbService.pending()) {
        if (!(await pushOne(p)).fullySent) break;
      }
    } catch (_) {
      // retry on the next trigger
    } finally {
      _running = false;
      await updateCount();
    }
  }
}
