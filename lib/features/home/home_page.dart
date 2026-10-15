import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_config.dart';
import '../../core/models/punch.dart';
import '../../core/models/roster.dart';
import '../../core/services/api_service.dart';
import '../../core/services/db_service.dart';
import '../../core/services/readiness_service.dart';
import '../../core/services/session.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/glo_theme.dart';
import '../../core/utils/hours.dart';
import '../../core/widgets/glo_widgets.dart';
import '../attendance/attendance_page.dart';
import '../enrollment/enrollment_page.dart';
import '../roster/roster_page.dart';
import 'profile_page.dart' show HomePageLabels;

/// Dashboard. Everything on it comes from this phone's real state or the server, nothing is fixed text.
class HomePage extends StatefulWidget {
  final VoidCallback? onSeeAll;
  const HomePage({super.key, this.onSeeAll});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<Punch> _recent = []; // newest first
  List<Punch> _today = []; // oldest first
  Shift? _shift;
  Readiness? _readiness;
  bool _offline = false;
  StreamSubscription? _conn;
  Timer? _tick;

  bool get _isRegular => Session.staffType == 'regular';

  bool get _hasInToday => _today.any((p) => p.type == 'IN');
  bool get _hasOutToday => _today.any((p) => p.type == 'OUT');

  /// Regular staff: one clock-in and one clock-out per day, so after the clock-out they are done.
  bool get _doneToday => _isRegular && _hasOutToday;

  /// Regular staff: clocked in today and not out yet. Shift and field staff just alternate,
  /// because their work can cross midnight.
  bool get _isClockedIn => _isRegular
      ? (_hasInToday && !_hasOutToday)
      : (_recent.isNotEmpty && _recent.first.type == 'IN');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncService.pending.addListener(_refresh);
    _conn = Connectivity().onConnectivityChanged.listen(_setOffline);
    Connectivity().checkConnectivity().then(_setOffline);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _refresh();
    _loadRemote();
    _loadReadiness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncService.pending.removeListener(_refresh);
    _conn?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the phone settings (for example after turning location on).
    if (state == AppLifecycleState.resumed) {
      _loadReadiness();
      _refresh(); // also picks up a new day if the app stayed open overnight
    }
  }

  void _setOffline(List<ConnectivityResult> r) {
    if (mounted) setState(() => _offline = r.every((x) => x == ConnectivityResult.none));
  }

  Future<void> _refresh() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final recent = await DbService.recent(limit: 30);
    final today = await DbService.since(midnight);
    if (mounted) {
      setState(() {
        _recent = recent;
        _today = today;
      });
    }
  }

  Future<void> _loadReadiness() async {
    final r = await Readiness.load();
    if (mounted) setState(() => _readiness = r);
  }

  Future<void> _loadRemote() async {
    Shift? shift;
    if (Session.staffType == 'shift') {
      try {
        final now = DateTime.now();
        final endOfDay = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        shift = (await ApiService.shifts())
            .where((s) => s.end.isAfter(now) && s.start.isBefore(endOfDay))
            .firstOrNull;
      } catch (_) {}
    }
    if (mounted) setState(() => _shift = shift);
  }

  Future<void> _openAttendance() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendancePage()));
    await _refresh();
    await _loadReadiness();
    if (mounted) setState(() {}); // enrolment state may have changed
  }

  Future<void> _openEnrollment() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const EnrollmentPage()));
    if (mounted) setState(() {});
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning,' : (h < 17 ? 'Good afternoon,' : 'Good evening,');
  }

  String _firstName() {
    final n = (Session.name ?? '').trim();
    return n.isEmpty ? (Session.staffId ?? '') : n.split(RegExp(r'\s+')).first;
  }


  String _todayLine() {
    if (_today.isEmpty) return 'No clock-ins yet today.';
    final now = DateTime.now();
    final w = workedFor(_today, DateTime(now.year, now.month, now.day), openUntil: now);
    final firstIn = _today.where((p) => p.type == 'IN').firstOrNull;
    return '${fmtDuration(w.worked)} ${w.open ? 'worked so far' : 'worked today'}'
        '${firstIn == null ? '' : '  •  first in ${DateFormat('HH:mm').format(firstIn.clientTime.toLocal())}'}';
  }

  Widget _syncButton() => ValueListenableBuilder<int>(
        valueListenable: SyncService.pending,
        builder: (_, n, __) => GestureDetector(
          onTap: () async {
            await SyncService.sync();
            await _refresh();
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: GloColors.border)),
              child: Icon(n == 0 && !_offline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: n == 0 && !_offline ? GloColors.primary : GloColors.amber),
            ),
            if (n > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: GloColors.amber, borderRadius: BorderRadius.circular(10)),
                  child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ),
      );

  Widget _statusChips() {
    final r = _readiness;
    final chips = <Widget>[];
    if (AppConfig.faceMode == 'match') {
      final label = !Session.faceEnrolled
          ? 'Face not enrolled'
          : (Session.faceStatus == 'confirmed' ? 'Face confirmed' : 'Face awaiting confirmation');
      chips.add(StatusChip(label: label, icon: Icons.face_rounded, color: Colors.white));
    } else {
      chips.add(const StatusChip(label: 'Photo check on', icon: Icons.photo_camera_rounded, color: Colors.white));
    }
    chips.add(StatusChip(
      label: r == null ? 'Checking device…' : (r.deviceBlocked ? 'Device check failed' : 'Device checks passed'),
      icon: Icons.phonelink_lock_rounded,
      color: Colors.white,
    ));
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _todayCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [GloColors.darkGreen, GloColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TODAY', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 7),
          Text(_doneToday ? 'Done for today' : (_isClockedIn ? 'You are clocked in' : 'Ready to clock in'),
              style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text(_todayLine(), style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12.5)),
          const SizedBox(height: 18),
          _statusChips(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: GloColors.darkGreen),
              onPressed: _doneToday ? null : _openAttendance,
              icon: Icon(_doneToday ? Icons.check_circle_rounded : Icons.fingerprint_rounded),
              label: Text(_doneToday ? 'Done for today' : (_isClockedIn ? 'Clock out' : 'Clock in')),
            ),
          ),
        ]),
      );

  Widget _shiftCard() {
    final s = _shift;
    return InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RosterScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: GloColors.border)),
        child: Row(children: [
          const Icon(Icons.calendar_month_rounded, color: GloColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Today's shift", style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                s == null
                    ? 'No shift rostered today'
                    : '${DateFormat('HH:mm').format(s.start)} – ${DateFormat('HH:mm').format(s.end)}${s.siteName.isEmpty ? '' : '  •  ${s.siteName}'}',
                style: const TextStyle(fontSize: 12, color: GloColors.muted),
              ),
            ]),
          ),
          const Text('Roster', style: TextStyle(fontWeight: FontWeight.w700, color: GloColors.darkGreen)),
          const Icon(Icons.chevron_right_rounded, color: GloColors.muted),
        ]),
      ),
    );
  }

  Widget _offlineBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: GloColors.amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [
          Icon(Icons.cloud_off_rounded, color: GloColors.amber),
          SizedBox(width: 10),
          Expanded(child: Text('You are offline. Clock-ins are saved on this phone and sent when you reconnect.', style: TextStyle(fontSize: 12.5))),
        ]),
      );

  Widget _identityTile() {
    if (AppConfig.faceMode != 'match') {
      return const AssuranceTile(icon: Icons.photo_camera_rounded, title: 'Photo check', subtitle: 'A photo is taken with each clock in');
    }
    if (!Session.faceEnrolled) {
      return GestureDetector(
        onTap: _openEnrollment,
        child: const AssuranceTile(icon: Icons.face_rounded, title: 'Face not enrolled', subtitle: 'Tap to enrol so your clock-ins can be checked', verified: false),
      );
    }
    final confirmed = Session.faceStatus == 'confirmed';
    return AssuranceTile(
      icon: Icons.face_rounded,
      title: 'Face enrolled',
      subtitle: confirmed ? 'Confirmed by your manager' : 'Waiting for your manager to confirm',
      verified: confirmed,
    );
  }

  Widget _locationTile() {
    final r = _readiness;
    if (r == null) return const AssuranceTile(icon: Icons.location_on_rounded, title: 'Work location', subtitle: 'Checking…', verified: false);
    final st = r.locationStatus(Session.staffType);
    return AssuranceTile(icon: Icons.location_on_rounded, title: st.title, subtitle: st.detail, verified: st.ok);
  }

  Widget _deviceTile() {
    final r = _readiness;
    if (r == null) return const AssuranceTile(icon: Icons.security_rounded, title: 'Device checks', subtitle: 'Checking this phone…', verified: false);
    if (r.deviceBlocked) {
      return AssuranceTile(icon: Icons.security_rounded, title: 'Device checks failed', subtitle: 'This phone cannot be used for attendance (${r.deviceProblem})', verified: false);
    }
    return AssuranceTile(
      icon: Icons.security_rounded,
      title: 'Device checks',
      subtitle: r.deviceClean ? 'This phone passed the security checks' : 'Passed (test build: ${r.deviceProblem})',
    );
  }

  Widget _recentCard() {
    if (_recent.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: GloColors.border)),
        child: const Row(children: [
          Icon(Icons.history_rounded, color: GloColors.primary),
          SizedBox(width: 12),
          Text('No clock-ins yet', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: GloColors.border)),
      child: Column(children: [
        for (final p in _recent.take(4))
          ListTile(
            leading: Icon(p.type == 'IN' ? Icons.login_rounded : Icons.logout_rounded, color: p.type == 'IN' ? GloColors.primary : GloColors.red),
            title: Text(p.type == 'IN' ? 'Clock in' : 'Clock out', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(DateFormat('EEE d MMM, HH:mm').format(p.clientTime.toLocal()), style: const TextStyle(fontSize: 12)),
            trailing: Icon(p.synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 20, color: p.synced ? GloColors.primary : GloColors.amber),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await SyncService.sync();
        await _loadRemote();
        await _loadReadiness();
        await _refresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            sliver: SliverToBoxAdapter(child: Row(children: [const GloLogo(size: 46), const Spacer(), _syncButton()])),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(), style: const TextStyle(color: GloColors.muted, fontSize: 14)),
                const SizedBox(height: 3),
                Text(_firstName(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: GloColors.ink)),
                const SizedBox(height: 3),
                Text('${HomePageLabels.type(Session.staffType)}  •  ${AppConfig.organizationName}', style: const TextStyle(color: GloColors.muted, fontSize: 12.5)),
              ]),
            ),
          ),
          if (_offline)
            SliverPadding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), sliver: SliverToBoxAdapter(child: _offlineBanner())),
          SliverPadding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 0), sliver: SliverToBoxAdapter(child: _todayCard())),
          if (Session.staffType == 'shift')
            SliverPadding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), sliver: SliverToBoxAdapter(child: _shiftCard())),
          const SliverPadding(padding: EdgeInsets.fromLTRB(20, 22, 20, 0), sliver: SliverToBoxAdapter(child: SectionTitle(title: 'Security posture'))),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(children: [_identityTile(), const SizedBox(height: 10), _locationTile(), const SizedBox(height: 10), _deviceTile()]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            sliver: SliverToBoxAdapter(child: SectionTitle(title: 'Recent activity', action: _recent.isEmpty ? null : 'See all', onAction: widget.onSeeAll)),
          ),
          SliverPadding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), sliver: SliverToBoxAdapter(child: _recentCard())),
        ],
      ),
    );
  }
}