import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'core/services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // The encrypted database, camera checks and device checks only exist on Android and iOS.
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'GLO EAMS runs on Android and iOS phones, not in a web browser.\n\n'
              'Connect a phone or start an Android emulator, then run:\nflutter run',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ),
      ),
    ));
    return;
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Session.load();
  runApp(const GloEamsApp());
}
