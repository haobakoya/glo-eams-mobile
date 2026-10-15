import '../models/punch.dart';

/// Hours worked from a day's punches (ascending by time).
/// A leading OUT is treated as an IN at [dayStart] (night shift continuing past midnight).
/// An unmatched IN counts until [openUntil] (pass "now" for today, null for past days).
({Duration worked, bool open}) workedFor(List<Punch> asc, DateTime dayStart,
    {DateTime? openUntil}) {
  var total = Duration.zero;
  DateTime? openIn;
  for (final p in asc) {
    final t = p.clientTime.toLocal();
    if (p.type == 'IN') {
      openIn ??= t;
    } else {
      final from = openIn ?? dayStart;
      if (t.isAfter(from)) total += t.difference(from);
      openIn = null;
    }
  }
  final open = openIn != null;
  if (openIn != null && openUntil != null && openUntil.isAfter(openIn)) {
    total += openUntil.difference(openIn);
  }
  return (worked: total, open: open);
}

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${h}h ${m}m';
}
