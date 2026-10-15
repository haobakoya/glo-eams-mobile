import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

class PunchException implements Exception {
  final String message;
  PunchException(this.message);
  @override
  String toString() => message;
}

class LocationService {
  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw PunchException('Turn on location services and try again.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw PunchException(
          'Location permission is required. Enable it in app settings.');
    }
    // iOS 14+ lets people share only an approximate location, which is far too coarse for a
    // 150 m geofence. Ask once for precise location for this clock-in.
    if (Platform.isIOS) {
      try {
        if (await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
          await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'ClockIn');
        }
      } catch (_) {
        // Fall through; the accuracy check on the clock-in screen will report it.
      }
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw PunchException('Could not get a GPS fix. Move to an open area.');
    }
  }

  /// Returns the first site whose geofence contains [pos], or null.
  static Site? matchSite(Position pos, List<Site> sites) {
    for (final s in sites) {
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, s.lat, s.lng);
      if (d <= s.radius) return s;
    }
    return null;
  }
}
