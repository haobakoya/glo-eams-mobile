import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

/// Client-side device checks. These raise the bar but a determined attacker can bypass them,
/// so the server also flags suspicious punches. Add Play Integrity / App Attest for real attestation.
class IntegrityService {
  /// Rooted phones and emulators are blocked in release builds and only flagged in debug builds.
  static bool blocks(List<String> flags) =>
      kReleaseMode && (flags.contains('ROOTED') || flags.contains('NOT_REAL_DEVICE'));

  static Future<List<String>> check() async {
    final flags = <String>[];
    try {
      if (await SafeDevice.isJailBroken) flags.add('ROOTED');
      if (!await SafeDevice.isRealDevice) flags.add('NOT_REAL_DEVICE');
      if (await SafeDevice.isDevelopmentModeEnable) flags.add('DEV_MODE');
    } catch (_) {
      // If the check itself fails, do not block the user; the server still reviews the punch.
    }
    return flags;
  }
}
