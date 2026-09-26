/// Why a sync run stopped. These values are not logged with tokens or mail.
sealed class SyncFailure implements Exception {
  const SyncFailure();
}

class Offline extends SyncFailure {
  const Offline();
}

class AuthExpired extends SyncFailure {
  const AuthExpired();
}

class ServerError extends SyncFailure {
  const ServerError();
}

class Rejected extends SyncFailure {
  const Rejected({required this.table, required this.id});

  final String table;
  final String id;
}

sealed class SyncStatus {
  const SyncStatus();
}

class SyncIdle extends SyncStatus {
  const SyncIdle();
}

class SyncSyncing extends SyncStatus {
  const SyncSyncing();
}

class SyncFailed extends SyncStatus {
  const SyncFailed(this.reason);

  final SyncFailure reason;
}

/// Shown when backup did not finish. The notes are still on this phone.
const String backupFailedCopy = "Couldn't back up · saved on this phone.";
