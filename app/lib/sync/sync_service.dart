import 'dart:async';

import '../storage/schema.dart';
import '../storage/sync_ledger.dart';
import 'auth.dart';
import 'failure.dart';
import 'ids.dart';
import 'merge.dart';
import 'remote.dart';

/// Pushes pending records, then pulls anything newer than the saved cursor.
///
/// One run at a time. A push is safe to retry: ids are client UUIDs, and a
/// row is marked synced only when its version is still the one that was sent.
///
/// The pull cursor is the last row's server `updated_at` and id. Rows from
/// one upsert share `updated_at`, so a time-only cursor would skip the rest
/// of that batch when a page ends in the middle of it.
class SyncService {
  SyncService({
    required this.ledger,
    required this.remote,
    required this.auth,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SyncLedger ledger;
  final NotebookRemote remote;
  final PaperSyncAuth auth;
  final Duration timeout;
  final DateTime Function() _now;

  static const _pageSize = 500;
  static const _batchSize = 200;
  static const _maxPasses = 40;
  static const _tombstoneRetention = Duration(days: 30);

  Future<SyncStatus>? _flight;

  bool get isRunning => _flight != null;

  Future<SyncStatus> run() {
    final existing = _flight;
    if (existing != null) return existing;
    late final Future<SyncStatus> flight;
    flight = _guarded().whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
    });
    _flight = flight;
    return flight;
  }

  Future<SyncStatus> _guarded() async {
    try {
      await _once();
      return const SyncIdle();
    } on AuthExpired {
      final refreshed = await auth.refreshSession();
      if (!refreshed) return const SyncFailed(AuthExpired());
      try {
        await _once();
        return const SyncIdle();
      } on SyncFailure catch (failure) {
        return SyncFailed(failure);
      } on Object {
        return const SyncFailed(ServerError());
      }
    } on SyncFailure catch (failure) {
      return SyncFailed(failure);
    } on Object {
      return const SyncFailed(ServerError());
    }
  }

  Future<void> _once() async {
    final account = auth.current;
    if (account == null) return;
    await ledger.claimUnowned(account.id);
    await _pushNotebooks(account.id);
    await _pushPages(account.id);
    await _pushStrokes(account.id);
    await _pullNotebooks();
    await _pullPages();
    await _pullStrokes();
    await ledger.purgeSyncedTombstones(
      syncedBefore: _now().subtract(_tombstoneRetention),
    );
  }

  Future<void> _pushNotebooks(String userId) async {
    var guard = 0;
    while (true) {
      if (++guard > _maxPasses) throw const ServerError();
      final pending = await ledger.pendingNotebooks(userId, limit: _batchSize);
      final ready = <NotebookSyncRow>[];
      for (final row in pending) {
        if (!isSyncUuid(row.id)) {
          await ledger.quarantine(SyncTables.notebooks, row.id);
          continue;
        }
        ready.add(row);
      }
      if (ready.isEmpty) {
        if (pending.isEmpty) return;
        continue;
      }
      try {
        await _call(remote.upsertNotebooks(ready));
      } on Rejected catch (failure) {
        await ledger.quarantine(failure.table, failure.id);
        continue;
      }
      for (final row in ready) {
        await ledger.markNotebookSynced(row.id, row.version);
      }
    }
  }

  Future<void> _pushPages(String userId) async {
    var guard = 0;
    while (true) {
      if (++guard > _maxPasses) throw const ServerError();
      final pending = await ledger.pendingPages(userId, limit: _batchSize);
      final ready = <PageSyncRow>[];
      for (final row in pending) {
        if (!isSyncUuid(row.id) || !isSyncUuid(row.notebookId)) {
          await ledger.quarantine(SyncTables.pages, row.id);
          continue;
        }
        ready.add(row);
      }
      if (ready.isEmpty) {
        if (pending.isEmpty) return;
        continue;
      }
      try {
        await _call(remote.upsertPages(ready));
      } on Rejected catch (failure) {
        await ledger.quarantine(failure.table, failure.id);
        continue;
      }
      for (final row in ready) {
        await ledger.markPageSynced(row.id, row.version);
      }
    }
  }

  Future<void> _pushStrokes(String userId) async {
    var guard = 0;
    while (true) {
      if (++guard > _maxPasses) throw const ServerError();
      final pending = await ledger.pendingStrokes(userId, limit: _batchSize);
      final ready = <StrokeSyncRow>[];
      for (final row in pending) {
        if (!isSyncUuid(row.id) || !isSyncUuid(row.pageId)) {
          await ledger.quarantine(SyncTables.strokes, row.id);
          continue;
        }
        ready.add(row);
      }
      if (ready.isEmpty) {
        if (pending.isEmpty) return;
        continue;
      }
      try {
        await _call(remote.upsertStrokes(ready));
      } on Rejected catch (failure) {
        await ledger.quarantine(failure.table, failure.id);
        continue;
      }
      for (final row in ready) {
        await ledger.markStrokeSynced(row.id, row.version);
      }
    }
  }

  Future<void> _pullNotebooks() async {
    var guard = 0;
    while (true) {
      if (++guard > _maxPasses) throw const ServerError();
      final cursor = await ledger.cursorFor(SyncTables.notebooks);
      final page = await _call(
        remote.pullNotebooks(
          after: cursor?.updatedAt,
          afterId: cursor?.id,
          limit: _pageSize,
        ),
      );
      if (page.isEmpty) return;
      for (final row in page) {
        final local = ledger.notebookRow(row.id);
        if (_takeRemote(
          localVersion: local?.version,
          localUpdatedAt: local?.updatedAt,
          localDeleted: local?.isDeleted ?? false,
          remote: row.version,
          remoteUpdatedAt: row.updatedAt,
          remoteDeleted: row.isDeleted,
        )) {
          await ledger.applyNotebook(row);
        }
      }
      final last = page.last;
      await ledger.setCursor(
        SyncTables.notebooks,
        SyncCursor(updatedAt: last.updatedAt, id: last.id),
      );
      if (page.length < _pageSize) return;
    }
  }

  Future<void> _pullPages() async {
    var guard = 0;
    while (true) {
      if (++guard > _maxPasses) throw const ServerError();
      final cursor = await ledger.cursorFor(SyncTables.pages);
      final page = await _call(
        remote.pullPages(
          after: cursor?.updatedAt,
          afterId: cursor?.id,
          limit: _pageSize,
        ),
      );
      if (page.isEmpty) return;
      for (final row in page) {
        final local = ledger.pageRow(row.id);
        if (_takeRemote(
          localVersion: local?.version,
          localUpdatedAt: local?.updatedAt,
          localDeleted: local?.isDeleted ?? false,
          remote: row.version,
          remoteUpdatedAt: row.updatedAt,
          remoteDeleted: row.isDeleted,
        )) {
          await ledger.applyPage(row);
        }
      }
      final last = page.last;
      await ledger.setCursor(
        SyncTables.pages,
        SyncCursor(updatedAt: last.updatedAt, id: last.id),
      );
      if (page.length < _pageSize) return;
    }
  }

  Future<void> _pullStrokes() async {
    var guard = 0;
    while (true) {
      if (++guard > _maxPasses) throw const ServerError();
      final cursor = await ledger.cursorFor(SyncTables.strokes);
      final page = await _call(
        remote.pullStrokes(
          after: cursor?.updatedAt,
          afterId: cursor?.id,
          limit: _pageSize,
        ),
      );
      if (page.isEmpty) return;
      for (final row in page) {
        final local = ledger.strokeRow(row.id);
        if (_takeRemote(
          localVersion: local?.version,
          localUpdatedAt: local?.updatedAt,
          localDeleted: local?.isDeleted ?? false,
          remote: row.version,
          remoteUpdatedAt: row.updatedAt,
          remoteDeleted: row.isDeleted,
        )) {
          await ledger.applyStroke(row);
        }
      }
      final last = page.last;
      await ledger.setCursor(
        SyncTables.strokes,
        SyncCursor(updatedAt: last.updatedAt, id: last.id),
      );
      if (page.length < _pageSize) return;
    }
  }

  bool _takeRemote({
    required int? localVersion,
    required DateTime? localUpdatedAt,
    required bool localDeleted,
    required int remote,
    required DateTime remoteUpdatedAt,
    required bool remoteDeleted,
  }) {
    return mergeRecord(
          localVersion: localVersion,
          localUpdatedAt: localUpdatedAt,
          localDeleted: localDeleted,
          remoteVersion: remote,
          remoteUpdatedAt: remoteUpdatedAt,
          remoteDeleted: remoteDeleted,
        ) ==
        MergeChoice.takeRemote;
  }

  Future<T> _call<T>(Future<T> future) {
    return future.timeout(timeout, onTimeout: () => throw const ServerError());
  }
}
