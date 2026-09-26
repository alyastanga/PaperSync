import '../storage/sync_ledger.dart';

/// The cloud side of sync. Implementations time out and map errors to
/// [SyncFailure] in the service, not in this interface.
abstract class NotebookRemote {
  Future<void> upsertNotebooks(List<NotebookSyncRow> rows);

  Future<void> upsertPages(List<PageSyncRow> rows);

  Future<void> upsertStrokes(List<StrokeSyncRow> rows);

  Future<List<NotebookSyncRow>> pullNotebooks({
    DateTime? after,
    int limit = 500,
  });

  Future<List<PageSyncRow>> pullPages({DateTime? after, int limit = 500});

  Future<List<StrokeSyncRow>> pullStrokes({DateTime? after, int limit = 500});
}
