import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/services/api_service.dart';
import '../../core/services/session.dart';
import '../../core/theme/glo_theme.dart';
import '../../core/widgets/glo_widgets.dart';
import '../attendance/face_capture_page.dart';

/// One-time face enrolment. The photo is captured live (with a blink or head-turn first),
/// sent to EAMS, and then confirmed by the person's manager.
/// Pops with true once the person is enrolled.
class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({super.key});
  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends State<EnrollmentPage> {
  String? photoPath;
  bool busy = false;
  bool consented = false;
  bool submitted = false;
  String? error;

  int get step => submitted ? 3 : (photoPath != null ? 2 : 1);

  @override
  void dispose() {
    _deletePhoto();
    super.dispose();
  }

  void _deletePhoto() {
    final p = photoPath;
    if (p != null) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
  }

  Future<bool> _consent() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enrol your face'),
        content: const Text('Your face is used to confirm that you are the person clocking in. '
            'A photo is taken with each clock in or out and compared with this enrolment. '
            'It is stored securely, used only for attendance, and your manager confirms the enrolment.\n\n'
            'Do you agree to your facial image being processed for this purpose?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('I agree'),
          ),
        ],
      ),
    );
    return go == true;
  }

  Future<void> capture() async {
    if (!consented) {
      if (!await _consent() || !mounted) return;
      consented = true;
    }
    final p = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const FaceCaptureScreen(title: 'Face enrolment', challenge: true)),
    );
    if (p == null || !mounted) return;
    _deletePhoto();
    setState(() {
      photoPath = p;
      error = null;
    });
  }

  Future<void> submit() async {
    final p = photoPath;
    if (p == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ApiService.enrolFace(File(p));
      await Session.setFaceEnrolled(true);
      if (Session.faceStatus == 'none') await Session.setFaceStatus('pending');
      _deletePhoto();
      if (mounted) {
        setState(() {
          photoPath = null;
          submitted = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final already = Session.faceEnrolled && !submitted;
    return Scaffold(
      appBar: AppBar(title: const Text('Identity enrolment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Row(children: [
              const GloLogo(size: 44),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Face enrolment', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                  Text('Your reference photo for clock-in checks', style: TextStyle(fontSize: 12, color: GloColors.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            if (already) ..._alreadyEnrolled() else if (submitted) ..._done() else ..._wizard(),
          ],
        ),
      ),
    );
  }

  List<Widget> _alreadyEnrolled() {
    final confirmed = Session.faceStatus == 'confirmed';
    return [
      AssuranceTile(
        icon: Icons.face_rounded,
        title: 'Face enrolled',
        subtitle: confirmed ? 'Confirmed by your manager' : 'Waiting for your manager to confirm',
        verified: confirmed,
      ),
      const SizedBox(height: 14),
      const Text('If your appearance has changed a lot, or the wrong person was enrolled, ask HR to reset your enrolment and then enrol again.',
          style: TextStyle(color: GloColors.muted, height: 1.5)),
      const SizedBox(height: 22),
      OutlinedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Back')),
    ];
  }

  List<Widget> _done() => [
        const _StepsBar(step: 3),
        const SizedBox(height: 28),
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(color: GloColors.lightGreen, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded, color: GloColors.primary, size: 76),
          ),
        ),
        const SizedBox(height: 22),
        const Text('Enrolment submitted', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        const Text('Your manager will confirm that the photo is you. Your clock-ins are checked against it from now on.',
            textAlign: TextAlign.center, style: TextStyle(color: GloColors.muted, height: 1.5)),
        const SizedBox(height: 26),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
      ];

  List<Widget> _wizard() => [
        _StepsBar(step: step),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: GloColors.lightGreen, borderRadius: BorderRadius.circular(19)),
          child: const Row(children: [
            Icon(Icons.verified_user_rounded, color: GloColors.darkGreen),
            SizedBox(width: 12),
            Expanded(
              child: Text('Your manager confirms the photo really is you. Until then your clock-ins are still checked.',
                  style: TextStyle(fontSize: 12.5, color: GloColors.darkGreen, height: 1.35, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Container(
          height: 330,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFF102019), borderRadius: BorderRadius.circular(26)),
          child: photoPath == null
              ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.face_retouching_natural_rounded, color: Colors.white, size: 74),
                  SizedBox(height: 16),
                  Text('Position your face in the guide', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('Good lighting  •  Look straight at the camera', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ])
              : Image.file(File(photoPath!), fit: BoxFit.cover, width: double.infinity),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: GloColors.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: GloColors.red),
              const SizedBox(width: 10),
              Expanded(child: Text(error!, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 17),
        ElevatedButton.icon(
          onPressed: busy ? null : capture,
          icon: const Icon(Icons.camera_alt_rounded),
          label: Text(photoPath == null ? 'Capture reference photo' : 'Retake photo'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: photoPath == null || busy ? null : submit,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(busy ? 'Submitting…' : 'Submit enrolment'),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Enrolment requirements'),
        const SizedBox(height: 11),
        const AssuranceTile(icon: Icons.wb_sunny_outlined, title: 'Clear image', subtitle: 'Good lighting, nothing covering your face'),
        const SizedBox(height: 9),
        const AssuranceTile(icon: Icons.visibility_outlined, title: 'Live person', subtitle: 'You will be asked to blink or turn your head'),
        const SizedBox(height: 9),
        AssuranceTile(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Manager confirmation',
          subtitle: AppConfig.faceMode == 'match' ? 'Your manager confirms the photo is you' : 'Not used in photo-only mode',
        ),
      ];
}

class _StepsBar extends StatelessWidget {
  const _StepsBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(children: [
        _Dot(number: '01', label: 'Capture', active: step >= 1),
        _Line(active: step >= 2),
        _Dot(number: '02', label: 'Submit', active: step >= 2),
        _Line(active: step >= 3),
        _Dot(number: '03', label: 'Manager review', active: step >= 3),
      ]);
}

class _Dot extends StatelessWidget {
  const _Dot({required this.number, required this.label, required this.active});
  final String number, label;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color: active ? GloColors.primary : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: active ? GloColors.primary : GloColors.border),
          ),
          child: Center(child: Text(number, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: active ? Colors.white : GloColors.muted))),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 9.5, color: GloColors.muted, fontWeight: FontWeight.w700)),
      ]);
}

class _Line extends StatelessWidget {
  const _Line({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) =>
      Expanded(child: Container(height: 2, margin: const EdgeInsets.only(bottom: 19), color: active ? GloColors.primary : GloColors.border));
}
