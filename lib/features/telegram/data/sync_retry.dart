/// How often a failed delivery is retried.
///
/// The delays grow so a dead bot token does not hammer the network, and the
/// attempts are capped so a job that can never succeed ends up in the send log
/// instead of retrying forever.
abstract final class SyncRetry {
  /// After this many failures the job is marked as failed.
  static const int maxAttempts = 8;

  /// 1, 2, 4, 8, 16, 32, 64 minutes for attempts 0..6 (then 64 minutes).
  static Duration delayFor(int attempts) {
    final exponent = attempts.clamp(0, 6);
    return Duration(minutes: 1 << exponent);
  }

  static bool canRetry(int attempts) => attempts < maxAttempts;
}
