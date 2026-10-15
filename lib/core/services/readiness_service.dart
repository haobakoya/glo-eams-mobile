import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'integrity_service.dart';

/// Live status of this phone and its work location, used by the dashboard, the clock-in screen and the profile.
/// A green tick for location means the phone is inside an approved work site (or the person is field staff),
/// never just that location permission is on.
class Readiness {
  final List<String> deviceFlags;
  final bool locationServicesOn;
  final bool locationPermissionOk;

  /// Approved work sites assigned to this person (the server only sends approved ones).
  final List<Site> sites;

  /// Closest approved site to the phone's last known position, and how far away it is. Null = no recent position.
  final Site? nearest;
  final double? distanceM;

  const Readiness(
    this.deviceFlags,
    this.locationServicesOn,
    this.locationPermissionOk, {
    this.sites = const [],
    this.nearest,
    this.distanceM,
  });

  bool get deviceBlocked => IntegrityService.blocks(deviceFlags);
  bool get deviceClean => deviceFlags.isEmpty;
  bool get locationOk => locationServicesOn && locationPermissionOk;
  bool get atSite => nearest != null && distanceM != null && distanceM! <= nearest!.radius;

  String get deviceProblem {
    if (deviceFlags.contains('ROOTED')) return 'rooted or jailbroken phone';
    if (deviceFlags.contains('NOT_REAL_DEVICE')) return 'emulator';
    if (deviceFlags.contains('DEV_MODE')) return 'developer mode is on';
    return '';
  }

  static String _dist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  /// What to show for "location". ok is true ONLY when the person can really clock in from here:
  /// location is on AND (field staff, or the phone is inside an approved site).
  ({String title, String detail, bool ok}) locationStatus(String? staffType) {
    if (!locationOk) {
      return (title: 'Location is off', detail: 'Turn on location and allow access to clock in.', ok: false);
    }
    if (staffType == 'field') {
      return (title: 'Field staff', detail: 'Your location is recorded when you clock in.', ok: true);
    }
    if (sites.isEmpty) {
      return (
        title: 'No approved work site',
        detail: 'No approved work site is assigned to you. Ask your manager or HR before you clock in.',
        ok: false,
      );
    }
    final near = nearest;
    final d = distanceM;
    if (near == null || d == null) {
      return (
        title: 'Work site not checked yet',
        detail: 'Your position is checked against ${sites.length == 1 ? sites.first.name : 'your approved sites'} when you clock in.',
        ok: false,
      );
    }
    if (atSite) {
      return (title: 'At ${near.name}', detail: 'Inside an approved work site (from your last known position).', ok: true);
    }
    return (
      title: 'Not at an approved work site',
      detail: 'About ${_dist(d)} from ${near.name} (last known position). You can only clock in at your approved site.',
      ok: false,
    );
  }

  static Future<Readiness> load() async {
    final flags = await IntegrityService.check();
    var on = false;
    var ok = false;
    try {
      on = await Geolocator.isLocationServiceEnabled();
      final p = await Geolocator.checkPermission();
      ok = p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {}

    final sites = await ApiService.sites();
    Site? nearest;
    double? dist;
    if (on && ok && sites.isNotEmpty) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null && !pos.isMocked) {
          dist = double.infinity;
          for (final s in sites) {
            final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, s.lat, s.lng);
            if (d < dist!) {
              dist = d;
              nearest = s;
            }
          }
          if (nearest == null) dist = null;
        }
      } catch (_) {
        nearest = null;
        dist = null;
      }
    }
    return Readiness(flags, on, ok, sites: sites, nearest: nearest, distanceM: dist == null || dist.isInfinite || dist.isNaN ? null : math.max(0, dist));
  }
}
