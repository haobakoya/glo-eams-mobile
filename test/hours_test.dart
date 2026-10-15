import 'package:glo_eams_mobile/core/models/punch.dart';
import 'package:glo_eams_mobile/core/utils/hours.dart';
import 'package:flutter_test/flutter_test.dart';

Punch punch(String type, DateTime t) => Punch(
      id: '$type${t.microsecondsSinceEpoch}',
      type: type,
      lat: 0,
      lng: 0,
      accuracy: 5,
      deviceId: 'd',
      clientTime: t.toUtc(),
    );

void main() {
  final day = DateTime(2026, 10, 5);
  DateTime at(int h, [int m = 0]) => day.add(Duration(hours: h, minutes: m));

  group('workedFor', () {
    test('pairs an IN with the next OUT', () {
      final r = workedFor([punch('IN', at(8)), punch('OUT', at(12))], day);
      expect(r.worked, const Duration(hours: 4));
      expect(r.open, isFalse);
    });

    test('adds several sessions in a day', () {
      final r = workedFor([
        punch('IN', at(8)), punch('OUT', at(12)),
        punch('IN', at(13)), punch('OUT', at(17)),
      ], day);
      expect(r.worked, const Duration(hours: 8));
    });

    test('an open IN counts until "now" on today', () {
      final r = workedFor([punch('IN', at(8))], day, openUntil: at(10));
      expect(r.worked, const Duration(hours: 2));
      expect(r.open, isTrue);
    });

    test('an open IN is not counted on past days but is reported as open', () {
      final r = workedFor([punch('IN', at(8))], day);
      expect(r.worked, Duration.zero);
      expect(r.open, isTrue);
    });

    test('a leading OUT counts from midnight (night shift)', () {
      final r = workedFor([punch('OUT', at(6))], day);
      expect(r.worked, const Duration(hours: 6));
    });

    test('a repeated IN keeps the first one', () {
      final r = workedFor([punch('IN', at(8)), punch('IN', at(9)), punch('OUT', at(10))], day);
      expect(r.worked, const Duration(hours: 2));
    });

    test('no punches means no hours', () {
      final r = workedFor([], day);
      expect(r.worked, Duration.zero);
      expect(r.open, isFalse);
    });
  });

  group('fmtDuration', () {
    test('formats hours and padded minutes', () {
      expect(fmtDuration(const Duration(hours: 8, minutes: 5)), '8h 05m');
      expect(fmtDuration(Duration.zero), '0h 00m');
      expect(fmtDuration(const Duration(hours: 10, minutes: 30)), '10h 30m');
    });
  });
}
