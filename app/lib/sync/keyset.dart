/// Whether [updatedAt] and [id] are strictly after a saved pull cursor.
///
/// One cloud upsert shares a single server `updated_at`, so two rows can
/// tie. A cursor that only stored that timestamp still includes the tie:
/// an older client may have stopped in the middle of the batch.
bool isAfterSyncCursor({
  required DateTime updatedAt,
  required String id,
  DateTime? after,
  String? afterId,
}) {
  if (after == null) return true;
  final byTime = updatedAt.compareTo(after);
  if (byTime > 0) return true;
  if (byTime < 0) return false;
  if (afterId == null || afterId.isEmpty) return true;
  return id.compareTo(afterId) > 0;
}
