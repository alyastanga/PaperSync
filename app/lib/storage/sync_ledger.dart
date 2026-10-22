import 'dart:typed_data';

import '../domain/ink.dart';

/// A notebook row the sync service can push, pull, and merge.
class NotebookSyncRow {
  const NotebookSyncRow({
    required this.id,
    required this.name,
    required this.inkColorArgb,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.syncState,
    this.deletedAt,
    this.ownerId,
  });

  final String id;
  final String name;
  final int inkColorArgb;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncState syncState;
  final String? ownerId;

  bool get isDeleted => deletedAt != null;
}

/// A page row, including a tombstone the library no longer shows.
class PageSyncRow {
  const PageSyncRow({
    required this.id,
    required this.notebookId,
    required this.pageIndex,
    required this.paperLeft,
    required this.paperTop,
    required this.paperWidth,
    required this.paperHeight,
    required this.recognizedText,
    required this.markers,
    required this.version,
    required this.createdAt,
    required this.capturedAt,
    required this.updatedAt,
    required this.syncState,
    this.deletedAt,
    this.ownerId,
  });

  final String id;
  final String notebookId;
  final int pageIndex;
  final double paperLeft;
  final double paperTop;
  final double paperWidth;
  final double paperHeight;
  final String recognizedText;
  final List<String> markers;
  final int version;
  final DateTime createdAt;
  final DateTime capturedAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncState syncState;
  final String? ownerId;

  bool get isDeleted => deletedAt != null;

  PaperRect get paperRect => PaperRect(
    leftMm: paperLeft,
    topMm: paperTop,
    widthMm: paperWidth,
    heightMm: paperHeight,
  );
}

/// A stroke row. [points] is the Phase 3 packed form.
class StrokeSyncRow {
  const StrokeSyncRow({
    required this.id,
    required this.pageId,
    required this.colorArgb,
    required this.width,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.syncState,
    required this.points,
    required this.timeOriginMs,
    this.deletedAt,
    this.ownerId,
  });

  final String id;
  final String pageId;
  final int colorArgb;
  final double width;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncState syncState;
  final String? ownerId;
  final Uint8List points;
  final int timeOriginMs;

  bool get isDeleted => deletedAt != null;
}

/// Where a pull left off.
///
/// [updatedAt] alone is not enough. One upsert is one database transaction,
/// and the server stamps every row in it with the same `updated_at`. A page
/// can end in the middle of that batch. [id] is the last row kept from it.
class SyncCursor {
  const SyncCursor({required this.updatedAt, this.id});

  final DateTime updatedAt;

  /// Null when the cursor was saved before ids were stored. The next pull
  /// re-reads every row at [updatedAt] so the rest of that batch is not lost.
  final String? id;

  String encode() {
    final time = updatedAt.toUtc().toIso8601String();
    final rowId = id;
    if (rowId == null || rowId.isEmpty) return time;
    return '$time|$rowId';
  }

  static SyncCursor? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final pipe = raw.lastIndexOf('|');
    if (pipe <= 0) {
      final time = DateTime.tryParse(raw);
      if (time == null) return null;
      return SyncCursor(updatedAt: time.toUtc());
    }
    final time = DateTime.tryParse(raw.substring(0, pipe));
    if (time == null) return null;
    final rowId = raw.substring(pipe + 1);
    return SyncCursor(
      updatedAt: time.toUtc(),
      id: rowId.isEmpty ? null : rowId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SyncCursor &&
        other.updatedAt == updatedAt &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(updatedAt, id);
}

/// Reads and writes the records sync is allowed to touch.
///
/// Pending rows stay on the same record as the ink. There is no second queue.
abstract class SyncLedger {
  Future<void> adoptUser(String? userId);

  /// Gives rows with no owner to [userId]. Rows owned by someone else stay.
  Future<void> claimUnowned(String userId);

  /// Notes for [userId] stay in the library after sign-out.
  Future<void> rememberHomeUser(String userId);

  Future<List<NotebookSyncRow>> pendingNotebooks(
    String userId, {
    int limit = 200,
  });

  Future<List<PageSyncRow>> pendingPages(String userId, {int limit = 200});

  Future<List<StrokeSyncRow>> pendingStrokes(String userId, {int limit = 200});

  NotebookSyncRow? notebookRow(String id);

  PageSyncRow? pageRow(String id);

  StrokeSyncRow? strokeRow(String id);

  /// False when the local version moved on while the upload was in flight.
  Future<bool> markNotebookSynced(String id, int version);

  Future<bool> markPageSynced(String id, int version);

  Future<bool> markStrokeSynced(String id, int version);

  Future<void> applyNotebook(NotebookSyncRow row);

  Future<void> applyPage(PageSyncRow row);

  Future<void> applyStroke(StrokeSyncRow row);

  Future<SyncCursor?> cursorFor(String table);

  Future<void> setCursor(String table, SyncCursor cursor);

  Future<void> quarantine(String table, String id);

  /// Drops tombstones that have been synced and are older than [syncedBefore].
  Future<int> purgeSyncedTombstones({required DateTime syncedBefore});
}
