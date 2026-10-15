import 'package:flutter/material.dart';
import '../../core/models/roster.dart';
import '../../core/services/api_service.dart';

/// Manager's queue of requests from their team.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<StaffRequest> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiService.pendingApprovals();
      if (mounted) setState(() { _items = r; _error = null; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _decide(StaffRequest r, bool approve) async {
    String? comment;
    if (!approve) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject request'),
          content: TextField(
              controller: c, maxLength: 300,
              decoration: const InputDecoration(labelText: 'Reason (optional)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      comment = c.text;
    }
    try {
      await ApiService.decide(r.id, approve, comment);
      if (mounted) setState(() => _items.removeWhere((x) => x.id == r.id));
      _toast(approve ? 'Approved' : 'Rejected');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
            : _error != null && _items.isEmpty
                ? ListView(children: [const SizedBox(height: 200), Center(child: Text(_error!))])
                : _items.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 200),
                        Center(child: Text('Nothing waiting for approval')),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final r in _items)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${r.staffName ?? r.staffId ?? ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                  const SizedBox(height: 2),
                                  Text('${StaffRequest.typeLabel(r.type)} · '
                                      '${r.fromDate == r.toDate ? r.fromDate : '${r.fromDate} to ${r.toDate}'}'),
                                  const SizedBox(height: 8),
                                  Text(r.reason),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _decide(r, false),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _decide(r, true),
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                  ]),
                                ]),
                              ),
                            ),
                        ],
                      ),
    );
  }
}
