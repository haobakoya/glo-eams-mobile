import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/services/api_service.dart';
import '../../core/services/db_service.dart';
import '../../core/services/readiness_service.dart';
import '../../core/services/session.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/glo_theme.dart';
import '../../core/widgets/glo_widgets.dart';
import '../auth/login_page.dart';
import '../enrollment/enrollment_page.dart';
import '../roster/roster_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<Site> _sites = [];
  Readiness? _readiness;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sites = await ApiService.sites();
    final r = await Readiness.load();
    if (mounted) setState(() { _sites = sites; _readiness = r; });
  }

  String get _identityText {
    if (AppConfig.faceMode != 'match') return 'Photo with each clock in';
    if (!Session.faceEnrolled) return 'Face not enrolled';
    return Session.faceStatus == 'confirmed' ? 'Face enrolled  •  confirmed by your manager' : 'Face enrolled  •  awaiting manager confirmation';
  }

  String get _deviceText {
    final id = Session.deviceId;
    final tail = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'Bound to this phone  •  ID …$tail';
  }

  Future<void> _signOut() async {
    final pending = await DbService.pendingCount();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(pending > 0
            ? '$pending clock-in(s) have not been sent yet. They stay encrypted on this phone and send after you sign in again.'
            : 'You will need to sign in again to clock in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    SyncService.stop();
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  Widget _row(IconData icon, String title, String subtitle) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      );

  @override
  Widget build(BuildContext context) {
    final r = _readiness;
    final work = _sites.isEmpty
        ? HomePageLabels.type(Session.staffType)
        : '${HomePageLabels.type(Session.staffType)}  •  ${_sites.map((s) => s.name).join(', ')}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      children: [
        const Align(alignment: Alignment.centerLeft, child: GloLogo(size: 58)),
        const SizedBox(height: 22),
        Text(Session.name ?? '', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(HomePageLabels.type(Session.staffType) + (Session.isManager ? '  •  Manager' : ''), style: const TextStyle(color: GloColors.muted)),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: GloColors.border)),
          child: Column(children: [
            _row(Icons.badge_outlined, 'Username', Session.staffId ?? ''),
            _row(Icons.apartment_rounded, 'Work context', work),
            _row(Icons.verified_user_outlined, 'Identity', _identityText),
            _row(Icons.phonelink_lock_rounded, 'Device', _deviceText),
          ]),
        ),
        const SizedBox(height: 16),
        AssuranceTile(
          icon: Icons.security_rounded,
          title: 'Security centre',
          subtitle: r == null ? 'Checking…' : (r.deviceBlocked ? 'This phone failed the device checks (${r.deviceProblem})' : 'This phone passed the device checks'),
          verified: r != null && !r.deviceBlocked,
        ),
        const SizedBox(height: 10),
        const AssuranceTile(
          icon: Icons.policy_outlined,
          title: 'Privacy',
          subtitle: 'Clock-in photos are stored securely, shown to your manager and deleted after a retention period',
        ),
        const SizedBox(height: 18),
        if (Session.staffType == 'shift')
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RosterScreen())),
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('My roster'),
          ),
        if (AppConfig.faceMode == 'match' && !Session.faceEnrolled) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const EnrollmentPage()));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.face_retouching_natural),
            label: const Text('Enrol my face'),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
        const SizedBox(height: 18),
        Center(child: Text('${AppConfig.productName}  •  ${AppConfig.organizationName}', style: const TextStyle(fontSize: 11, color: GloColors.muted))),
      ],
    );
  }
}

/// Small shared label helper (kept here so Home and Profile show the same wording).
class HomePageLabels {
  static String type(String? t) =>
      switch (t) { 'shift' => 'Shift staff', 'field' => 'Field staff', _ => 'Office staff' };
}
