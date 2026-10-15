import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/roster.dart';
import '../../core/services/api_service.dart';

Color statusColor(String s) => switch (s) {
      'approved' => Colors.green.shade700,
      'rejected' => Colors.red.shade700,
      _ => Colors.orange.shade800,
    };

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
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
      final r = await ApiService.myRequests();
      if (mounted) setState(() { _items = r; _error = null; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _new() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const NewRequestScreen()));
    if (ok == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Request sent to your manager')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
            : _error != null && _items.isEmpty
                ? ListView(children: [const SizedBox(height: 200), Center(child: Text(_error!))])
                : _items.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 200),
                        Center(child: Text('No requests yet')),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        children: [for (final r in _items) _tile(r)],
                      ),
      ),
    );
  }

  Widget _tile(StaffRequest r) => Card(
        child: ListTile(
          title: Text(StaffRequest.typeLabel(r.type),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${r.fromDate == r.toDate ? r.fromDate : '${r.fromDate} to ${r.toDate}'}\n${r.reason}'
              '${r.managerComment == null ? '' : '\nManager: ${r.managerComment}'}'),
          isThreeLine: true,
          trailing: Chip(
            label: Text(r.status.toUpperCase(),
                style: TextStyle(color: statusColor(r.status), fontWeight: FontWeight.w700, fontSize: 11)),
          ),
        ),
      );
}

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});
  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  String _type = 'leave';
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _fmt = DateFormat('yyyy-MM-dd');

  Future<void> _pick(bool isFrom) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _from = d;
        if (_to.isBefore(d)) _to = d;
      } else {
        _to = d.isBefore(_from) ? _from : d;
      }
    });
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please give a reason.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ApiService.createRequest(
        type: _type,
        fromDate: _fmt.format(_from),
        toDate: _fmt.format(_to),
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final single = _type != 'leave';
    return Scaffold(
      appBar: AppBar(title: const Text('New request')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Request type'),
            items: const [
              DropdownMenuItem(value: 'leave', child: Text('Leave')),
              DropdownMenuItem(value: 'overtime', child: Text('Overtime')),
              DropdownMenuItem(value: 'correction', child: Text('Attendance correction')),
            ],
            onChanged: (v) => setState(() {
              _type = v ?? 'leave';
              if (_type != 'leave') _to = _from;
            }),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(single ? 'Date' : 'From'),
            trailing: Text(DateFormat('EEE d MMM yyyy').format(_from)),
            onTap: () => _pick(true),
          ),
          if (!single)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available),
              title: const Text('To'),
              trailing: Text(DateFormat('EEE d MMM yyyy').format(_to)),
              onTap: () => _pick(false),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: _type == 'correction'
                  ? 'What needs correcting? (e.g. forgot to clock out at 17:00)'
                  : 'Reason',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
