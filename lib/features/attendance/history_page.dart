/*import 'package:flutter/material.dart';
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
*/

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/history_sync.dart';

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
  List<Punch> _items = []; // Oldest first.

  bool _loading = false;
  String? _loadError;
  Future<void>? _loadFuture;
  bool _hasLoadedSuccessfully = false;

  @override
  void initState() {
    super.initState();
    SyncService.pending.addListener(_onPendingChanged);
    _load();
  }

  @override
  void dispose() {
    SyncService.pending.removeListener(_onPendingChanged);
    super.dispose();
  }

  void _onPendingChanged() {
    _load();
  }

  /// Loads local attendance records without modifying or deleting them.
  ///
  /// Concurrent requests share the same future so that a sync notification
  /// and a manual refresh do not start competing database reads.
  Future<void> _load() {
    final existing = _loadFuture;
    if (existing != null) return existing;

    final future = _performLoad();
    _loadFuture = future;

    return future.whenComplete(() {
      if (identical(_loadFuture, future)) {
        _loadFuture = null;
      }
    });
  }

  Future<void> _performLoad() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      await HistorySync.pullIfNeeded();
      final since = DateTime.now().subtract(
        const Duration(days: 30),
      );

      final records = await DbService.since(since);

      if (!mounted) return;

      setState(() {
        _items = records;
        _hasLoadedSuccessfully = true;
        _loadError = null;
      });
    } catch (e, st) {
      debugPrint('History database read failed: $e\n$st');

      if (!mounted) return;

      setState(() {
                _loadError = 'Unable to load attendance history.\n\nDetails: $e';
       // _loadError =
         //   'Unable to load attendance history. '
           // 'Your existing attendance records have not been deleted '
            //'by this screen. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await SyncService.sync();
    } catch (e, st) {
      debugPrint('History sync request failed: $e\n$st');
    } finally {
      await _load();
    }
  }

  List<Widget> _days(BuildContext context) {
    final groups = <DateTime, List<Punch>>{};

    for (final p in _items) {
      final local = p.clientTime.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      (groups[day] ??= []).add(p);
    }

    final days = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <Widget>[];

    for (final day in days) {
      final punches = groups[day]!;
      final isToday = day == today;

      final worked = workedFor(
        punches,
        day,
        openUntil: isToday ? now : null,
      );

      out.add(
        Container(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            dense: true,
            title: Text(
              isToday ? 'Today' : DateFormat('EEEE d MMM').format(day),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: worked.open && !isToday
                ? const Text(
                    'Missing clock-out. Request a correction.',
                    style: TextStyle(color: Colors.orange),
                  )
                : null,
            trailing: Text(
              fmtDuration(worked.worked),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );

      // The database returns oldest first; display newest first per day.
      for (final p in punches.reversed) {
        out.add(
          ListTile(
            leading: Icon(
              p.type == 'IN' ? Icons.login : Icons.logout,
              color: p.type == 'IN'
                  ? GloColors.primary
                  : GloColors.red,
            ),
            title: Text(p.type == 'IN' ? 'Clock in' : 'Clock out'),
            subtitle: Text(
              DateFormat('HH:mm').format(p.clientTime.toLocal()),
            ),
            trailing: Icon(
              p.synced ? Icons.cloud_done : Icons.cloud_off,
              size: 20,
              color: p.synced
                  ? GloColors.primary
                  : GloColors.amber,
            ),
          ),
        );
      }
    }

    return out;
  }

  Widget _errorMessage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: GloColors.amber),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'History could not be loaded',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_loadError!),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;

    if (_loading && !_hasLoadedSuccessfully) {
        content = ListView(
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    } else if (_loadError != null && !_hasLoadedSuccessfully) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          _errorMessage(),
        ],
      );
    } else if (_items.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_loadError != null) _errorMessage(),
          if (_loading)
            const LinearProgressIndicator(),
          const SizedBox(height: 180),
          const Center(
            child: Text('No punches in the last 30 days'),
          ),
        ],
      );
    } else {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_loadError != null) _errorMessage(),
          if (_loading) const LinearProgressIndicator(),
          ..._days(context),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: content,
      ),
    );
  }
}