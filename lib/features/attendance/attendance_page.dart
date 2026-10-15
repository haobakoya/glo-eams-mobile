import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/config/app_config.dart';
import '../../core/models/punch.dart';
import '../../core/models/push_result.dart';
import '../../core/services/api_service.dart';
import '../../core/services/db_service.dart';
import '../../core/services/integrity_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/readiness_service.dart';
import '../../core/services/session.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/glo_theme.dart';
import '../../core/widgets/glo_widgets.dart';
import '../enrollment/enrollment_page.dart';
import 'face_capture_page.dart';

enum _Phase { ready, running, success, saved, review, rejected, needsEnrolment, doneToday }

enum _Step { device, location, face, record }

enum _St { pending, active, done, failed }

/// The clock in/out journey. Every stage shown here is a real check; nothing is simulated.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  _Phase phase = _Phase.ready;
  final Map<_Step, _St> steps = {for (final s in _Step.values) s: _St.pending};
  Readiness? readiness;
  bool isOut = false;
  Position? position;
  Site? site;
  String? error;
  DateTime? completedAt;
  PushResult result = PushResult.none;

  bool get running => phase == _Phase.running;

  @override
  void initState() {
    super.initState();
    _loadReady();
  }

  Future<void> _loadReady() async {
    final recent = await DbService.recent(limit: 20);
    final r = await Readiness.load();

    final now = DateTime.now();
    bool isToday(DateTime t) {
      final l = t.toLocal();
      return l.year == now.year && l.month == now.month && l.day == now.day;
    }

    final today = recent.where((p) => isToday(p.clientTime)).toList();
    final hasIn = today.any((p) => p.type == 'IN');
    final hasOut = today.any((p) => p.type == 'OUT');

    if (!mounted) return;
    setState(() {
      readiness = r;
      if (Session.staffType == 'regular') {
        // Regular staff: one clock-in and one clock-out per day.
        if (hasOut) {
          phase = _Phase.doneToday;
        } else {
          isOut = hasIn;
        }
      } else {
        // Shift and field staff can work across midnight, so they simply alternate.
        isOut = recent.isNotEmpty && recent.first.type == 'IN';
      }
    });
  }

  void _set(_Step s, _St v) {
    if (mounted) setState(() => steps[s] = v);
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      for (final e in steps.entries.toList()) {
        if (e.value == _St.active) steps[e.key] = _St.failed;
      }
      error = msg;
      phase = _Phase.rejected;
    });
  }

  Future<bool> _ensureNotice() async {
    if (await Session.readRaw('selfieNoticeOk') == '1') return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Photo with each clock in/out'),
        content: const Text('A photo is taken every time you clock in or out. It is stored securely, '
            'used only to confirm attendance, may be reviewed by your manager, '
            'and is deleted after a limited period.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await Session.writeRaw('selfieNoticeOk', '1');
    return true;
  }

  Future<void> _run() async {
    if (running) return; // ignore double taps
    setState(() {
      phase = _Phase.running;
      error = null;
      for (final s in _Step.values) {
        steps[s] = _St.pending;
      }
    });
    try {
      // 1. Device security
      _set(_Step.device, _St.active);
      final flags = await IntegrityService.check();
      if (IntegrityService.blocks(flags)) {
        throw PunchException('This phone does not meet the security requirements for attendance (rooted or emulated device).');
      }
      _set(_Step.device, _St.done);

      // 2. Location and work site
      _set(_Step.location, _St.active);
      final pos = await LocationService.current();
      if (pos.isMocked) {
        throw PunchException('Mock location detected. Turn it off and try again.');
      }
      if (pos.accuracy > AppConfig.maxAccuracyMeters) {
        throw PunchException('GPS accuracy is too low (±${pos.accuracy.round()} m). Move to an open area and try again.');
      }
      Site? matched;
      if (Session.staffType != 'field') {
        final sites = await ApiService.sites();
        matched = LocationService.matchSite(pos, sites);
        if (matched == null) {
          throw PunchException(sites.isEmpty
              ? 'No work site is assigned to you yet. Contact your manager or HR.'
              : 'You are not within an approved work site.');
        }
      }
      position = pos;
      site = matched;
      _set(_Step.location, _St.done);

      // 3. Face check (camera opens on its own screen)
      String? selfie;
      _set(_Step.face, _St.active);
      if (AppConfig.faceRequired) {
        if (AppConfig.faceMode == 'match') {
          if (!Session.faceEnrolled) {
            _set(_Step.face, _St.pending);
            if (mounted) setState(() => phase = _Phase.needsEnrolment);
            return;
          }
        } else if (!await _ensureNotice()) {
          throw PunchException('Please accept the photo notice to continue.');
        }
        if (!mounted) return;
        selfie = await Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => FaceCaptureScreen(
            title: isOut ? 'Clock out' : 'Clock in',
            challenge: AppConfig.livenessChallenge,
          ),
        ));
        if (selfie == null) throw PunchException('Photo cancelled. Nothing was recorded.');
      }
      _set(_Step.face, _St.done);

      // 4. Record: saved on the phone first, then sent
      _set(_Step.record, _St.active);
      final punch = Punch(
        id: const Uuid().v4(),
        type: isOut ? 'OUT' : 'IN',
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        siteId: matched?.id,
        deviceId: Session.deviceId,
        clientTime: DateTime.now().toUtc(),
        selfiePath: selfie,
        hasSelfie: selfie != null,
        deviceFlags: flags,
      );
      await DbService.insert(punch);
      HapticFeedback.mediumImpact();
      await SyncService.updateCount();

      PushResult r;
      try {
        r = await SyncService.pushOne(punch).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        r = PushResult.none; // still queued; the background sync will finish it
      }
      await SyncService.updateCount();
      if (!mounted) return;
      setState(() {
        steps[_Step.record] = _St.done;
        result = r;
        completedAt = DateTime.now();
        phase = !r.punchSynced ? _Phase.saved : (r.needsReview ? _Phase.review : _Phase.success);
      });
      SyncService.sync();
    } on PunchException catch (e) {
      _fail(e.message);
    } on ApiException catch (e) {
      _fail(e.message);
    } catch (e) {
      debugPrint('attendance failed: $e');
      _fail('Something went wrong. Please try again.');
    }
  }

  Future<void> _enrolThenRetry() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const EnrollmentPage()));
    if (ok == true && Session.faceEnrolled && mounted) {
      await _run();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !running,
      child: Scaffold(
        backgroundColor: GloColors.surface,
        appBar: AppBar(
          title: Text(phase == _Phase.doneToday ? 'Attendance' : (isOut ? 'Clock out' : 'Clock in')),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: KeyedSubtree(key: ValueKey(phase), child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    switch (phase) {
      case _Phase.ready:
        return _ReadyView(readiness: readiness, isOut: isOut, onStart: _run);
      case _Phase.running:
        return _RunningView(steps: steps);
      case _Phase.success:
      case _Phase.saved:
      case _Phase.review:
        return _ResultView(
          icon: phase == _Phase.success ? Icons.check_circle_rounded : (phase == _Phase.saved ? Icons.save_alt_rounded : Icons.hourglass_top_rounded),
          color: phase == _Phase.success ? GloColors.primary : GloColors.amber,
          headline: switch (phase) {
            _Phase.success => isOut ? 'CLOCK-OUT RECORDED' : 'CLOCK-IN RECORDED',
            _Phase.saved => 'SAVED ON THIS PHONE',
            _ => isOut ? 'CLOCK-OUT RECORDED' : 'CLOCK-IN RECORDED',
          },
          time: DateFormat('HH:mm').format(completedAt ?? DateTime.now()),
          subtitle: site?.name ?? (Session.staffType == 'field' ? 'Field location' : ''),
          note: switch (phase) {
            _Phase.saved => 'No connection right now. It is stored securely and sends automatically when you are online.',
            _Phase.review => 'Your manager may take a quick look to confirm this one.',
            _ => null,
          },
          rows: _rows(),
          primary: 'Done',
          onPrimary: () => Navigator.pop(context),
        );
      case _Phase.rejected:
        return _ResultView(
          icon: Icons.error_outline_rounded,
          color: GloColors.red,
          headline: 'COULD NOT RECORD',
          note: error ?? 'EAMS could not complete this clock-in.',
          primary: 'Try again',
          onPrimary: () => setState(() => phase = _Phase.ready),
          secondary: 'Cancel',
          onSecondary: () => Navigator.pop(context),
        );
      case _Phase.needsEnrolment:
        return _ResultView(
          icon: Icons.face_retouching_natural,
          color: GloColors.darkGreen,
          headline: 'ENROL YOUR FACE FIRST',
          note: 'Your clock-ins are checked against a reference photo. It takes a minute and you only do it once.',
          primary: 'Enrol now',
          onPrimary: _enrolThenRetry,
          secondary: 'Cancel',
          onSecondary: () => Navigator.pop(context),
        );
      case _Phase.doneToday:
        return _ResultView(
          icon: Icons.check_circle_rounded,
          color: GloColors.primary,
          headline: 'DONE FOR TODAY',
          note: 'You have already clocked in and out today. See you tomorrow.',
          primary: 'Close',
          onPrimary: () => Navigator.pop(context),
        );
    }
  }

  List<(String, String)> _rows() {
    final String face;
    if (!AppConfig.faceRequired) {
      face = 'Not required';
    } else if (AppConfig.faceMode == 'match') {
      face = switch (result.faceStatus) {
        'matched' => 'Matched',
        'mismatch' => 'Did not match',
        'unverified' => 'Could not be checked',
        'not_enrolled' => 'Not enrolled',
        _ => result.selfieSynced ? 'Photo sent' : 'Photo saved, sending later',
      };
    } else {
      face = result.selfieSynced ? 'Photo sent' : 'Photo saved, sending later';
    }
    final r = readiness;
    return [
      ('Face check', face),
      ('Device', r == null || r.deviceClean ? 'Checks passed' : 'Passed (test build)'),
      ('GPS accuracy', position == null ? '-' : '±${position!.accuracy.toStringAsFixed(0)} m'),
      ('Status', result.punchSynced ? 'Sent to EAMS' : 'Saved, will send when online'),
    ];
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.readiness, required this.isOut, required this.onStart});
  final Readiness? readiness;
  final bool isOut;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final r = readiness;
    final match = AppConfig.faceMode == 'match';
    final identity = !match
        ? ('A photo is taken with each clock in or out', true)
        : (!Session.faceEnrolled
            ? ('Not enrolled yet. You will enrol before this clock-in.', false)
            : (Session.faceStatus == 'confirmed' ? ('Enrolled and confirmed by your manager', true) : ('Enrolled, waiting for your manager to confirm', false)));
    final device = r == null
        ? ('Checking this phone…', false)
        : (r.deviceBlocked ? ('Not allowed: ${r.deviceProblem}', false) : ('Security checks passed', true));
    final loc = r?.locationStatus(Session.staffType);
    final location = r == null ? ('Checking…', false) : ('${loc!.title}. ${loc.detail}', loc.ok);
    final hasSite = Session.staffType == 'field' || (r != null && r.sites.isNotEmpty);
    final context0 = (switch (Session.staffType) {
      'field' => 'Field staff: your location is recorded, not restricted',
      _ => r == null
          ? 'Checking…'
          : (r.sites.isEmpty
              ? 'No approved work site is assigned to you yet'
              : 'Approved site: ${r.sites.map((s) => s.name).join(', ')}${Session.staffType == 'shift' ? '. Your rostered shift is checked too' : ''}'),
    }, hasSite);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        const Align(alignment: Alignment.centerLeft, child: GloLogo(size: 48)),
        const SizedBox(height: 26),
        const Text('Secure attendance', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Before your attendance is recorded, EAMS checks your device, location and face.',
            style: TextStyle(color: GloColors.muted, height: 1.5)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: GloColors.border)),
          child: Column(children: [
            _ReadyRow(icon: Icons.verified_user_rounded, title: 'Identity', subtitle: identity.$1, ok: identity.$2),
            const Divider(height: 26),
            _ReadyRow(icon: Icons.phonelink_lock_rounded, title: 'Device', subtitle: device.$1, ok: device.$2),
            const Divider(height: 26),
            _ReadyRow(icon: Icons.location_on_rounded, title: 'Location', subtitle: location.$1, ok: location.$2),
            const Divider(height: 26),
            _ReadyRow(icon: Icons.schedule_rounded, title: 'Work context', subtitle: context0.$1, ok: context0.$2),
          ]),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: (r?.deviceBlocked ?? false) ? null : onStart,
          icon: const Icon(Icons.fingerprint_rounded),
          label: Text(isOut ? 'Begin clock-out' : 'Begin clock-in'),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text('Saved on your phone first, then checked by EAMS server controls.', style: TextStyle(fontSize: 11.5, color: GloColors.muted)),
        ),
      ],
    );
  }
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({required this.icon, required this.title, required this.subtitle, required this.ok});
  final IconData icon;
  final String title, subtitle;
  final bool ok;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 42, height: 42, decoration: const BoxDecoration(color: GloColors.lightGreen, shape: BoxShape.circle), child: Icon(icon, color: GloColors.darkGreen, size: 21)),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: GloColors.muted, height: 1.35)),
          ]),
        ),
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ok ? GloColors.primary : GloColors.amber, size: 20),
      ]);
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.steps});
  final Map<_Step, _St> steps;

  static const _labels = {
    _Step.device: 'Device security',
    _Step.location: 'Location and work site',
    _Step.face: 'Face check',
    _Step.record: 'Recording attendance',
  };

  @override
  Widget build(BuildContext context) {
    final active = steps.entries.firstWhere((e) => e.value == _St.active, orElse: () => const MapEntry(_Step.device, _St.pending)).key;
    final (IconData, String, String) info = switch (active) {
      _Step.device => (Icons.phonelink_lock_rounded, 'Checking your device', 'Looking for rooting, emulators and tampering.'),
      _Step.location => (Icons.location_on_rounded, 'Checking your location', 'Getting a current GPS position and matching your work site.'),
      _Step.face => (Icons.face_rounded, 'Face check', 'The camera opens next. Follow the on-screen instruction.'),
      _Step.record => (Icons.shield_rounded, 'Recording your attendance', 'Saving securely on your phone and sending to EAMS.'),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              color: GloColors.lightGreen,
              shape: BoxShape.circle,
              border: Border.all(color: GloColors.primary.withValues(alpha: 0.18), width: 9),
            ),
            child: Icon(info.$1, color: GloColors.darkGreen, size: 52),
          ),
          const SizedBox(height: 28),
          Text(info.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(info.$3, textAlign: TextAlign.center, style: const TextStyle(color: GloColors.muted, height: 1.5)),
          const SizedBox(height: 28),
          for (final e in steps.entries)
            Padding(padding: const EdgeInsets.only(bottom: 11), child: _StepRow(label: _labels[e.key]!, state: e.value)),
        ]),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});
  final String label;
  final _St state;

  @override
  Widget build(BuildContext context) {
    final Widget lead = switch (state) {
      _St.done => const Icon(Icons.check_circle_rounded, color: GloColors.primary, size: 20),
      _St.failed => const Icon(Icons.cancel_rounded, color: GloColors.red, size: 20),
      _St.active => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      _St.pending => const Icon(Icons.radio_button_unchecked_rounded, color: GloColors.border, size: 20),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: GloColors.border)),
      child: Row(children: [
        lead,
        const SizedBox(width: 11),
        Expanded(
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: state == _St.pending ? GloColors.muted : GloColors.ink)),
        ),
      ]),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.icon,
    required this.color,
    required this.headline,
    required this.primary,
    required this.onPrimary,
    this.time,
    this.subtitle,
    this.note,
    this.rows,
    this.secondary,
    this.onSecondary,
  });
  final IconData icon;
  final Color color;
  final String headline, primary;
  final VoidCallback onPrimary;
  final String? time, subtitle, note, secondary;
  final List<(String, String)>? rows;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 64),
          ),
          const SizedBox(height: 24),
          Text(headline, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color == GloColors.primary ? GloColors.darkGreen : GloColors.ink)),
          if (time != null) ...[
            const SizedBox(height: 8),
            Text(time!, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
          ],
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: GloColors.muted)),
          ],
          if (note != null) ...[
            const SizedBox(height: 12),
            Text(note!, textAlign: TextAlign.center, style: const TextStyle(color: GloColors.muted, height: 1.5)),
          ],
          if (rows != null) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: GloColors.border)),
              child: Column(children: [
                for (var i = 0; i < rows!.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  _InfoRow(label: rows![i].$1, value: rows![i].$2),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: onPrimary, child: Text(primary))),
          if (secondary != null) TextButton(onPressed: onSecondary, child: Text(secondary!)),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: GloColors.muted))),
        Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
      ]);
}