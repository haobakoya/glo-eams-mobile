import 'package:flutter_test/flutter_test.dart';
import 'package:glo_eams_mobile/core/models/push_result.dart';
import 'package:glo_eams_mobile/core/services/api_service.dart';
import 'package:glo_eams_mobile/core/services/readiness_service.dart';

void main() {
  group('PushResult.needsReview', () {
    test('a clean punch does not need review', () {
      const r = PushResult(punchSynced: true, selfieSynced: true, faceStatus: 'matched');
      expect(r.needsReview, isFalse);
      expect(r.fullySent, isTrue);
    });

    test('plain low GPS accuracy alone does not need review', () {
      const r = PushResult(punchSynced: true, selfieSynced: true, flags: ['LOW_ACCURACY']);
      expect(r.needsReview, isFalse);
    });

    test('other flags need review', () {
      const r = PushResult(punchSynced: true, selfieSynced: true, flags: ['OUTSIDE_GEOFENCE']);
      expect(r.needsReview, isTrue);
    });

    test('a face mismatch, unreadable or missing enrolment needs review', () {
      for (final s in ['mismatch', 'unverified', 'not_enrolled']) {
        expect(PushResult(punchSynced: true, selfieSynced: true, faceStatus: s).needsReview, isTrue, reason: s);
      }
    });

    test('nothing sent yet means not fully sent', () {
      expect(PushResult.none.fullySent, isFalse);
      expect(PushResult.none.punchSynced, isFalse);
    });
  });

  group('Readiness', () {
    test('a clean phone with location on is ready', () {
      const r = Readiness([], true, true);
      expect(r.deviceClean, isTrue);
      expect(r.locationOk, isTrue);
      expect(r.deviceProblem, '');
    });

    test('location needs both the service and the permission', () {
      expect(const Readiness([], true, false).locationOk, isFalse);
      expect(const Readiness([], false, true).locationOk, isFalse);
    });

    test('problems are described in plain words', () {
      expect(const Readiness(['ROOTED'], true, true).deviceProblem, contains('rooted'));
      expect(const Readiness(['NOT_REAL_DEVICE'], true, true).deviceProblem, contains('emulator'));
      expect(const Readiness(['DEV_MODE'], true, true).deviceProblem, contains('developer'));
      expect(const Readiness(['DEV_MODE'], true, true).deviceClean, isFalse);
    });
  });

  group('Readiness.locationStatus', () {
    final hq = Site('1', 'Head Office', 6.4281, 3.4219, 150);

    test('location off is never a tick', () {
      final st = const Readiness([], false, true).locationStatus('regular');
      expect(st.ok, isFalse);
      expect(st.title, 'Location is off');
    });

    test('permission denied is never a tick', () {
      expect(const Readiness([], true, false).locationStatus('regular').ok, isFalse);
    });

    test('no approved site is not a tick, even with location on', () {
      final st = const Readiness([], true, true).locationStatus('regular');
      expect(st.ok, isFalse);
      expect(st.title, 'No approved work site');
    });

    test('field staff are ticked once location is on', () {
      expect(const Readiness([], true, true).locationStatus('field').ok, isTrue);
    });

    test('an assigned site but no position yet is not a tick', () {
      final st = Readiness(const [], true, true, sites: [hq]).locationStatus('shift');
      expect(st.ok, isFalse);
      expect(st.detail, contains('Head Office'));
    });

    test('inside the site radius is a tick', () {
      final r = Readiness(const [], true, true, sites: [hq], nearest: hq, distanceM: 90);
      expect(r.atSite, isTrue);
      final st = r.locationStatus('regular');
      expect(st.ok, isTrue);
      expect(st.title, 'At Head Office');
    });

    test('outside the radius is not a tick and says how far', () {
      final r = Readiness(const [], true, true, sites: [hq], nearest: hq, distanceM: 2400);
      expect(r.atSite, isFalse);
      final st = r.locationStatus('regular');
      expect(st.ok, isFalse);
      expect(st.title, 'Not at an approved work site');
      expect(st.detail, contains('2.4 km'));
    });
  });
}
