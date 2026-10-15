import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/roster.dart';
import '../../core/services/api_service.dart';

/// Manager checks: confirm new face enrolments, and spot-check clock-in photos
/// (automatic mismatches, other flagged punches and a random sample).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<ReviewItem> _items = [];
  List<EnrolItem> _enrols = [];
  final Map<String, Future<Uint8List>> _photos = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await ApiService.reviewQueue();
      final e = await ApiService.enrolments();
      if (mounted) setState(() { _items = q; _enrols = e; _error = null; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _more() async {
    try {
      final n = await ApiService.reviewSample(5);
      _toast(n == 0 ? 'No more recent photos to check' : '$n photos added');
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _confirmEnrol(EnrolItem it, bool ok) async {
    try {
      await ApiService.confirmEnrolment(it.id, ok);
      _photos.remove('e:${it.id}');
      if (mounted) setState(() => _enrols.removeWhere((x) => x.id == it.id));
      _toast(ok ? 'Enrolment confirmed' : '${it.staffName} will be asked to enrol again');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _decide(ReviewItem it, bool ok) async {
    String? comment;
    if (!ok) {
      final c = TextEditingController();
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Flag this photo'),
          content: TextField(
            controller: c,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'What looks wrong? (optional)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Flag for HR'),
            ),
          ],
        ),
      );
      if (go != true) return;
      comment = c.text;
    }
    try {
      await ApiService.reviewDecide(it.id, ok, comment);
      _photos.remove('p:${it.id}');
      if (mounted) setState(() => _items.removeWhere((x) => x.id == it.id));
      _toast(ok ? 'Marked as fine' : 'Flagged for HR');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Widget _photo(String key, Future<Uint8List> Function() load) {
    final f = _photos[key] ??= load();
    return SizedBox(
      height: 280,
      width: double.infinity,
      child: FutureBuilder<Uint8List>(
        future: f,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return const Center(child: Icon(Icons.broken_image, size: 48));
          }
          return Image.memory(snap.data!, fit: BoxFit.cover);
        },
      ),
    );
  }

  Widget? _faceChip(String status) {
    final (String, Color)? v = switch (status) {
      'matched' => ('Face matched', Colors.green.shade700),
      'mismatch' => ('Face did not match', Colors.red.shade700),
      'unverified' => ('Face could not be checked', Colors.orange.shade800),
      'not_enrolled' => ('No face enrolled', Colors.orange.shade800),
      _ => null,
    };
    if (v == null) return null;
    return Chip(
      avatar: Icon(Icons.face, size: 16, color: v.$2),
      label: Text(v.$1, style: TextStyle(color: v.$2, fontWeight: FontWeight.w600, fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _enrolCard(EnrolItem it) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _photo('e:${it.id}', () => ApiService.enrolmentPhotoBytes(it.id)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Is this ${it.staffName.isEmpty ? it.staffId : it.staffName}?',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('This photo will be used to check every clock in. '
                  'Confirm only if you recognise the person.'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => _confirmEnrol(it, false), child: const Text('No, reject')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: () => _confirmEnrol(it, true), child: const Text('Yes, that\'s them')),
                ),
              ]),
            ]),
          ),
        ]),
      );

  Widget _card(ReviewItem it) {
    final chip = _faceChip(it.faceStatus);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _photo('p:${it.id}', () => ApiService.selfieBytes(it.id)),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.staffName.isEmpty ? it.staffId : it.staffName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text('${it.type == 'IN' ? 'Clock in' : 'Clock out'} · '
                '${DateFormat('EEE d MMM, HH:mm').format(it.time)}'
                '${it.siteName.isEmpty ? '' : ' · ${it.siteName}'}'),
            if (chip != null || it.flags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (chip != null) chip,
                for (final f in it.flags)
                  if (!f.startsWith('FACE_'))
                    Chip(
                      label: Text(f, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => _decide(it, false), child: const Text('Doesn\'t look right')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                    onPressed: () => _decide(it, true), child: const Text('Looks fine')),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null && _items.isEmpty && _enrols.isEmpty)
                  Center(child: Text(_error!)),
                if (_enrols.isNotEmpty) ...[
                  Text('New face enrolments (${_enrols.length})', style: t.titleMedium),
                  const SizedBox(height: 8),
                  for (final e in _enrols) _enrolCard(e),
                  const SizedBox(height: 16),
                ],
                Row(children: [
                  Expanded(
                    child: Text(
                      _items.isEmpty ? 'No photos waiting' : '${_items.length} photos to check',
                      style: t.titleMedium,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _more,
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('Check more'),
                  ),
                ]),
                const SizedBox(height: 8),
                for (final it in _items) _card(it),
              ],
            ),
    );
  }
}
