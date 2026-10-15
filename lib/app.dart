import 'package:flutter/material.dart';
import 'core/config/app_config.dart';
import 'core/services/session.dart';
import 'core/theme/glo_theme.dart';
import 'features/auth/login_page.dart';
import 'features/home/shell_page.dart';

class GloEamsApp extends StatelessWidget {
  const GloEamsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppConfig.productName,
        theme: GloTheme.light(),
        home: Session.loggedIn ? const ShellPage() : const LoginPage(),
      );
}
