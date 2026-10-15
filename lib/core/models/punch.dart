class Punch {
  final String id; // UUID, makes server sync idempotent
  final String type; // IN | OUT
  final double lat, lng, accuracy;
  final String? siteId;
  final String deviceId;
  final DateTime clientTime; // UTC
  final bool synced;
  final String? selfiePath; // local file until uploaded, then null
  final bool hasSelfie;
  final bool selfieSynced;
  final List<String> deviceFlags;

  Punch({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.deviceId,
    required this.clientTime,
    this.siteId,
    this.synced = false,
    this.selfiePath,
    this.hasSelfie = false,
    this.selfieSynced = false,
    this.deviceFlags = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'site_id': siteId,
        'device_id': deviceId,
        'client_time': clientTime.toIso8601String(),
        'synced': synced ? 1 : 0,
        'selfie_path': selfiePath,
        'has_selfie': hasSelfie ? 1 : 0,
        'selfie_synced': selfieSynced ? 1 : 0,
        'device_flags': deviceFlags.join(','),
      };

  factory Punch.fromMap(Map<String, dynamic> m) {
    final flags = (m['device_flags'] as String?) ?? '';
    return Punch(
      id: m['id'] as String,
      type: m['type'] as String,
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      accuracy: (m['accuracy'] as num).toDouble(),
      siteId: m['site_id'] as String?,
      deviceId: m['device_id'] as String,
      clientTime: DateTime.parse(m['client_time'] as String),
      synced: (m['synced'] as int) == 1,
      selfiePath: m['selfie_path'] as String?,
      hasSelfie: (m['has_selfie'] as int?) == 1,
      selfieSynced: (m['selfie_synced'] as int?) == 1,
      deviceFlags: flags.isEmpty ? const [] : flags.split(','),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'siteId': siteId,
        'deviceId': deviceId,
        'clientTime': clientTime.toIso8601String(),
        'deviceFlags': deviceFlags,
        'hasSelfie': hasSelfie,
      };
}
