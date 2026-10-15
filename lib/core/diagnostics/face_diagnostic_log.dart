
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

class FaceDiagnosticLog {
  static File? _file;

  static Future<File> _getFile() async {
    if (_file != null) return _file!;

    final directory = await getApplicationDocumentsDirectory();
    _file = File('${directory.path}/face_diagnostics.txt');

    if (!await _file!.exists()) {
      await _file!.create(recursive: true);
    }

    return _file!;
  }

  static Future<void> write(String message) async {
    try {
      final file = await _getFile();
      final timestamp = DateTime.now().toIso8601String();

      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
        flush: true,
      );

      debugPrint(message);
    } catch (e) {
      debugPrint('FACE LOG WRITE ERROR: $e');
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _getFile();
      await file.writeAsString('', flush: true);
    } catch (e) {
      debugPrint('FACE LOG CLEAR ERROR: $e');
    }
  }

  static Future<void> share() async {
    try {
      final file = await _getFile();

      if (await file.length() == 0) {
        await write('No diagnostic events have been recorded yet.');
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'GLO EAMS face-enrolment diagnostic log',
        ),
      );
    } catch (e) {
      debugPrint('FACE LOG SHARE ERROR: $e');
    }
  }
}