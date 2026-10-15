import 'package:glo_eams_mobile/core/models/punch.dart';
import 'package:glo_eams_mobile/core/models/roster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Punch', () {
    final p = Punch(
      id: 'abc',
      type: 'IN',
      lat: 6.5244,
      lng: 3.3792,
      accuracy: 8.5,
      siteId: 's1',
      deviceId: 'dev',
      clientTime: DateTime.utc(2026, 10, 5, 7, 30),
      selfiePath: '/tmp/x.jpg',
      hasSelfie: true,
      deviceFlags: const ['DEV_MODE', 'ROOTED'],
    );

    test('survives a trip through the local database map', () {
      final back = Punch.fromMap(p.toMap());
      expect(back.id, 'abc');
      expect(back.type, 'IN');
      expect(back.clientTime, DateTime.utc(2026, 10, 5, 7, 30));
      expect(back.selfiePath, '/tmp/x.jpg');
      expect(back.hasSelfie, isTrue);
      expect(back.deviceFlags, ['DEV_MODE', 'ROOTED']);
      expect(back.synced, isFalse);
    });

    test('an empty flag list stays empty', () {
      final q = Punch(
          id: 'x', type: 'OUT', lat: 0, lng: 0, accuracy: 1, deviceId: 'd',
          clientTime: DateTime.utc(2026, 1, 1));
      expect(Punch.fromMap(q.toMap()).deviceFlags, isEmpty);
    });

    test('the server payload carries what the API expects', () {
      final j = p.toJson();
      expect(j['id'], 'abc');
      expect(j['siteId'], 's1');
      expect(j['deviceFlags'], ['DEV_MODE', 'ROOTED']);
      expect(j['hasSelfie'], isTrue);
      expect(j['clientTime'], endsWith('Z')); // UTC
      expect(j.containsKey('selfiePath'), isFalse); // local path never leaves the phone
    });
  });

  group('Shift', () {
    test('treats server times as UTC even when the Z is missing', () {
      final s = Shift.fromJson({
        'id': '1', 'siteName': 'HQ',
        'start': '2026-10-05T07:00:00', 'end': '2026-10-05T16:00:00Z',
      });
      expect(s.start.toUtc(), DateTime.utc(2026, 10, 5, 7));
      expect(s.end.toUtc(), DateTime.utc(2026, 10, 5, 16));
    });
  });

  group('requests and reviews', () {
    test('request type labels', () {
      expect(StaffRequest.typeLabel('leave'), 'Leave');
      expect(StaffRequest.typeLabel('correction'), 'Attendance correction');
    });

    test('a review item reads its flags and local time', () {
      final r = ReviewItem.fromJson({
        'id': 'p1', 'staffName': 'A B', 'staffId': 'ab', 'type': 'IN',
        'siteName': null, 'clientTime': '2026-10-05T07:00:00Z',
        'flags': ['OUTSIDE_GEOFENCE'],
      });
      expect(r.flags, ['OUTSIDE_GEOFENCE']);
      expect(r.siteName, '');
      expect(r.time.toUtc(), DateTime.utc(2026, 10, 5, 7));
      expect(r.faceStatus, '');
      expect(r.faceScore, isNull);
    });

    test('a review item reads the automatic face result', () {
      final r = ReviewItem.fromJson({
        'id': 'p2', 'staffName': 'C D', 'staffId': 'cd', 'type': 'OUT',
        'siteName': 'HQ', 'clientTime': '2026-10-05T16:00:00Z',
        'flags': ['FACE_MISMATCH'], 'faceStatus': 'mismatch', 'faceScore': 0.21,
      });
      expect(r.faceStatus, 'mismatch');
      expect(r.faceScore, closeTo(0.21, 1e-9));
    });

    test('an enrolment item reads its fields', () {
      final e = EnrolItem.fromJson({'id': 'g1', 'staffName': 'E F', 'staffId': 'ef'});
      expect(e.id, 'g1');
      expect(e.staffName, 'E F');
    });
  });
}
