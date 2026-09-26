/// Which copy of a record survives a pull.
enum MergeChoice { keepLocal, takeRemote }

/// Higher version wins. The same version uses the later [remoteUpdatedAt],
/// and a tombstone wins ties with a live row. A lower remote version never
/// replaces a local row, including one that is still pending.
MergeChoice mergeRecord({
  required int? localVersion,
  required DateTime? localUpdatedAt,
  required bool localDeleted,
  required int remoteVersion,
  required DateTime remoteUpdatedAt,
  required bool remoteDeleted,
}) {
  if (localVersion == null) return MergeChoice.takeRemote;
  if (remoteVersion > localVersion) return MergeChoice.takeRemote;
  if (remoteVersion < localVersion) return MergeChoice.keepLocal;
  if (remoteDeleted && !localDeleted) return MergeChoice.takeRemote;
  if (localDeleted && !remoteDeleted) return MergeChoice.keepLocal;
  final localTime = localUpdatedAt;
  if (localTime == null || remoteUpdatedAt.isAfter(localTime)) {
    return MergeChoice.takeRemote;
  }
  return MergeChoice.keepLocal;
}
