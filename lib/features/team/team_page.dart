import 'package:flutter/material.dart';
import '../../core/theme/glo_theme.dart';
import 'approvals_page.dart';
import 'review_page.dart';

/// Manager area: request approvals and photo checks.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My team'),
          bottom: const TabBar(
            labelColor: GloColors.darkGreen,
            unselectedLabelColor: GloColors.muted,
            indicatorColor: GloColors.primary,
            tabs: [Tab(text: 'Approvals'), Tab(text: 'Photo checks')],
          ),
        ),
        body: const TabBarView(children: [ApprovalsScreen(), ReviewScreen()]),
      ),
    );
  }
}
