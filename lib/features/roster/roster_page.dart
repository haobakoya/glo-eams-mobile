import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/roster.dart';
import '../../core/services/api_service.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});
  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  List<Shift> _shifts = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ApiService.shifts();
      if (mounted) setState(() { _shifts = s; _error = null; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return DateFormat('EEEE d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('My roster')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
            : _error != null && _shifts.isEmpty
                ? ListView(children: [const SizedBox(height: 200), Center(child: Text(_error!))])
                : _shifts.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 200),
                        Center(child: Text('No shifts assigned. Contact your supervisor.')),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final s in _shifts)
                            Card(
                              color: (s.start.isBefore(now) && s.end.isAfter(now))
                                  ? const Color(0x2E4FA44D)
                                  : null,
                              child: ListTile(
                                leading: const Icon(Icons.schedule),
                                title: Text(_dayLabel(s.start),
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    '${DateFormat('HH:mm').format(s.start)} – ${DateFormat('HH:mm').format(s.end)}'
                                    '${s.siteName.isEmpty ? '' : '\n${s.siteName}'}'),
                                isThreeLine: s.siteName.isNotEmpty,
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}
