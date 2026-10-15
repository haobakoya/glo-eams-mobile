import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/punch.dart';
import '../../core/theme/glo_theme.dart';
import '../../core/services/db_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/utils/hours.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Punch> _items = []; // oldest first

  @override
  void initState() {
    super.initState();
    SyncService.pending.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncService.pending.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final r = await DbService.since(since);
    if (mounted) setState(() => _items = r);
  }

  List<Widget> _days(BuildContext context) {
    final groups = <DateTime, List<Punch>>{};
    for (final p in _items) {
      final l = p.clientTime.toLocal();
      (groups[DateTime(l.year, l.month, l.day)] ??= []).add(p);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <Widget>[];
    for (final day in days) {
      final isToday = day == today;
      final w = workedFor(groups[day]!, day, openUntil: isToday ? now : null);
      out.add(Container(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          dense: true,
          title: Text(isToday ? 'Today' : DateFormat('EEEE d MMM').format(day),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: w.open && !isToday
              ? const Text('Missing clock-out. Request a correction.',
                  style: TextStyle(color: Colors.orange))
              : null,
          trailing: Text(fmtDuration(w.worked),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ));
      for (final p in groups[day]!.reversed) {
        out.add(ListTile(
          leading: Icon(p.type == 'IN' ? Icons.login : Icons.logout,
              color: p.type == 'IN' ? GloColors.primary : GloColors.red),
          title: Text(p.type == 'IN' ? 'Clock in' : 'Clock out'),
          subtitle: Text(DateFormat('HH:mm').format(p.clientTime.toLocal())),
          trailing: Icon(p.synced ? Icons.cloud_done : Icons.cloud_off,
              size: 20, color: p.synced ? GloColors.primary : GloColors.amber),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncService.sync();
          await _load();
        },
        child: _items.isEmpty
            ? ListView(children: const [
                SizedBox(height: 200),
                Center(child: Text('No punches in the last 30 days')),
              ])
            : ListView(children: _days(context)),
      ),
    );
  }
}
