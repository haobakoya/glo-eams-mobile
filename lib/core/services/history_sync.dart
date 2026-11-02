import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'db_service.dart';

/// Rebuilds this phone's local punch history from the server.
///
/// Runs only when it is needed: the local database is empty, or it was found unreadable
/// and replaced by an empty one (DbService.resetThisRun). Safe to call from several
/// screens at once, and it never throws: offline or any error simply means "skip for now".
class HistorySync {
  static Future<void>? _running;

  static Future<void> pullIfNeeded({int days = 30}) {
    return _running ??= _pullIfNeeded(days).whenComplete(() => _running = null);
  }

  static Future<void> _pullIfNeeded(int days) async {
    try {
      final needed =
          DbService.resetThisRun || (await DbService.recent(limit: 1)).isEmpty;
      if (!needed) return;

      // Short timeout so a weak connection never holds up clock-in.
      final rows = await ApiService.myPunchRows(days: days)
          .timeout(const Duration(seconds: 6));

      await DbService.mergeRemote(rows);
      DbService.resetThisRun = false;
    } catch (e) {
      debugPrint('HistorySync: skipped: $e');
    }
  }
}