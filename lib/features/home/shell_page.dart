import 'package:flutter/material.dart';
import '../../core/services/session.dart';
import '../../core/services/sync_service.dart';
import '../../core/widgets/glo_widgets.dart';
import '../attendance/history_page.dart';
import '../requests/requests_page.dart';
import '../team/team_page.dart';
import 'home_page.dart';
import 'profile_page.dart';

class _Tab {
  final GloNavItem item;
  final Widget page;
  const _Tab(this.item, this.page);
}

/// Bottom navigation: Home, History, Requests, Team (managers only), Profile.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _i = 0;
  late final List<_Tab> _tabs;

  @override
  void initState() {
    super.initState();
    SyncService.start();
    _tabs = [
      _Tab(const GloNavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
          HomePage(onSeeAll: () => setState(() => _i = 1))),
      const _Tab(GloNavItem(Icons.history_rounded, Icons.history_rounded, 'History'), HistoryScreen()),
      const _Tab(GloNavItem(Icons.assignment_outlined, Icons.assignment_rounded, 'Requests'), RequestsScreen()),
      if (Session.isManager)
        const _Tab(GloNavItem(Icons.groups_outlined, Icons.groups_rounded, 'Team'), TeamScreen()),
      const _Tab(GloNavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'), ProfilePage()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _i, children: [for (final t in _tabs) t.page]),
      ),
      bottomNavigationBar: GloBottomNav(
        index: _i,
        onChanged: (v) => setState(() => _i = v),
        items: [for (final t in _tabs) t.item],
      ),
    );
  }
}
