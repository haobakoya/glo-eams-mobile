class AppConfig {
  static const productName = 'GLO EAMS';
  static const organizationName = 'Globacom Limited';

  /// The EAMS attendance API. No trailing slash. If the API sits behind a /api path on your reverse
  /// proxy, either strip that prefix at the proxy or set PathBase=/api on the API.
  static const baseUrl = 'https://attendance.gloworld.com';

  /// Reject GPS fixes less accurate than this (metres).
  static const maxAccuracyMeters = 50.0;

  /// Default site radius if the server does not supply one (metres).
  static const defaultRadiusMeters = 150.0;

  /// Take a photo with every punch (all staff types).
  static const faceRequired = true;

  /// 'match'  = one-time enrolment, then every punch is matched automatically on the server.
  ///            Mismatches are flagged (never blocked) and go to the manager's photo queue.
  /// 'selfie' = photo is stored and spot-checked by the manager only (no enrolment, no matching).
  static const faceMode = 'match';

  /// Ask for a blink or head turn before the photo is taken (stops a photo of a photo).
  static const livenessChallenge = true;

  /// Certificate pinning: when true the app trusts ONLY the CA certificate in assets/certs/server_ca.pem
  /// for API calls. Leave false until that file is added (then every request fails if it is missing or wrong).
  static const pinServerCertificate = false;

  static const syncInterval = Duration(minutes: 2);
  static const requestTimeout = Duration(seconds: 360);
}
