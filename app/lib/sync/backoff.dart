const Duration syncBackoffCap = Duration(minutes: 5);

/// 5 seconds, doubled on each failure, capped at 5 minutes, plus [jitterMs].
Duration syncBackoff(int failureCount, {int jitterMs = 0}) {
  final count = failureCount < 1 ? 1 : failureCount;
  var seconds = 5;
  for (var i = 1; i < count; i++) {
    if (seconds >= syncBackoffCap.inSeconds) break;
    seconds *= 2;
  }
  if (seconds > syncBackoffCap.inSeconds) seconds = syncBackoffCap.inSeconds;
  final jitter = jitterMs < 0 ? 0 : (jitterMs > 1000 ? 1000 : jitterMs);
  return Duration(seconds: seconds, milliseconds: jitter);
}
