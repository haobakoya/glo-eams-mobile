class Shift {
  final String id, siteName;
  final DateTime start, end; // local time
  Shift(this.id, this.siteName, this.start, this.end);

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        j['id'].toString(),
        (j['siteName'] ?? '') as String,
        _utc(j['start'] as String).toLocal(),
        _utc(j['end'] as String).toLocal(),
      );

  // The server sends UTC; make sure a missing "Z" does not make it local time.
  static DateTime _utc(String s) =>
      DateTime.parse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
}

class StaffRequest {
  final String id, type, fromDate, toDate, reason, status;
  final String? managerComment, staffName, staffId;
  StaffRequest({
    required this.id,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.reason,
    required this.status,
    this.managerComment,
    this.staffName,
    this.staffId,
  });

  factory StaffRequest.fromJson(Map<String, dynamic> j) => StaffRequest(
        id: j['id'].toString(),
        type: j['type'] as String,
        fromDate: j['fromDate'] as String,
        toDate: j['toDate'] as String,
        reason: (j['reason'] ?? '') as String,
        status: (j['status'] ?? 'pending') as String,
        managerComment: j['managerComment'] as String?,
        staffName: j['staffName'] as String?,
        staffId: j['staffId'] as String?,
      );

  static String typeLabel(String t) => switch (t) {
        'leave' => 'Leave',
        'overtime' => 'Overtime',
        'correction' => 'Attendance correction',
        _ => t,
      };
}

/// A clock-in photo waiting for the manager's check.
class ReviewItem {
  final String id, staffName, staffId, type, siteName;
  final DateTime time; // local
  final List<String> flags;
  final String faceStatus; // matched | mismatch | unverified | not_enrolled | captured | ''
  final double? faceScore;
  ReviewItem({
    required this.id,
    required this.staffName,
    required this.staffId,
    required this.type,
    required this.siteName,
    required this.time,
    required this.flags,
    this.faceStatus = '',
    this.faceScore,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        id: j['id'].toString(),
        staffName: (j['staffName'] ?? '') as String,
        staffId: (j['staffId'] ?? '') as String,
        type: (j['type'] ?? 'IN') as String,
        siteName: (j['siteName'] ?? '') as String,
        time: Shift._utc(j['clientTime'] as String).toLocal(),
        flags: ((j['flags'] ?? []) as List).map((e) => e.toString()).toList(),
        faceStatus: (j['faceStatus'] ?? '') as String,
        faceScore: (j['faceScore'] as num?)?.toDouble(),
      );
}

/// A team member whose face enrolment is waiting for the manager to confirm.
class EnrolItem {
  final String id, staffName, staffId;
  EnrolItem({required this.id, required this.staffName, required this.staffId});

  factory EnrolItem.fromJson(Map<String, dynamic> j) => EnrolItem(
        id: j['id'].toString(),
        staffName: (j['staffName'] ?? '') as String,
        staffId: (j['staffId'] ?? '') as String,
      );
}
