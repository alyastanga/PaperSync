import '../storage/sync_ledger.dart';
import 'keyset.dart';

/// The cloud side of sync. Implementations time out and map errors to
/// [SyncFailure] in the service, not in this interface.
abstract class NotebookRemote {
  Future<void> upsertNotebooks(List<NotebookSyncRow> rows);

  Future<void> upsertPages(List<PageSyncRow> rows);

  Future<void> upsertStrokes(List<StrokeSyncRow> rows);

  /// Rows after [after] / [afterId]. See [isAfterSyncCursor].
  Future<List<NotebookSyncRow>> pullNotebooks({
    DateTime? after,
    String? afterId,
    int limit = 500,
  });

  /// Rows after [after] / [afterId]. See [isAfterSyncCursor].
  Future<List<PageSyncRow>> pullPages({
    DateTime? after,
    String? afterId,
    int limit = 500,
  });

  /// Rows after [after] / [afterId]. See [isAfterSyncCursor].
  Future<List<StrokeSyncRow>> pullStrokes({
    DateTime? after,
    String? afterId,
    int limit = 500,
  });
}
