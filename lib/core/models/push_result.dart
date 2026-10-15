/// What happened when one punch was sent to the server.
class PushResult {
  final bool punchSynced;
  final bool selfieSynced;
  final List<String> flags;
  final String? faceStatus; // matched | mismatch | unverified | not_enrolled | captured

  const PushResult({
    required this.punchSynced,
    required this.selfieSynced,
    this.flags = const [],
    this.faceStatus,
  });

  /// Nothing reached the server (offline). The punch stays queued on the phone.
  static const none = PushResult(punchSynced: false, selfieSynced: false);

  bool get fullySent => punchSynced && selfieSynced;

  /// Mirrors the server's own rule for the manager's photo queue (plain low GPS accuracy excepted),
  /// plus any automatic face result that was not a clean match.
  bool get needsReview =>
      flags.any((f) => f != 'LOW_ACCURACY') ||
      const {'mismatch', 'unverified', 'not_enrolled'}.contains(faceStatus);
}
