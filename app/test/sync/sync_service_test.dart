import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/storage/notebook_store.dart';
import 'package:papersync/storage/schema.dart';
import 'package:papersync/storage/sync_ledger.dart';
import 'package:papersync/sync/auth.dart';
import 'package:papersync/sync/failure.dart';
import 'package:papersync/sync/keyset.dart';
import 'package:papersync/sync/remote.dart';
import 'package:papersync/sync/sync_service.dart';

const _user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _notebookId = '11111111-1111-4111-8111-111111111111';
const _pageId = '22222222-2222-4222-8222-222222222222';
const _strokeId = '33333333-3333-4333-8333-333333333333';
const _badId = '44444444-4444-4444-8444-444444444444';
const _otherNotebook = '55555555-5555-4555-8555-555555555555';

String _batchId(int n) {
  final tail = n.toRadixString(16).padLeft(12, '0');
  return '10000000-0000-4000-8000-$tail';
}

void main() {
  test('a retried push does not duplicate the row', () async {
    final store = _store();
    final remote = _FakeRemote()..failAfterWrite = 1;
    final service = _service(store, remote);
    await store.createNotebook(_notebook(), ownerId: _user);

    final first = await service.run();
    expect(first, isA<SyncFailed>());
    expect(remote.notebooks, hasLength(1));
    expect((await store.pendingNotebooks(_user)), hasLength(1));

    final second = await service.run();
    expect(second, isA<SyncIdle>());
    expect(remote.notebooks, hasLength(1));
    expect((await store.pendingNotebooks(_user)), isEmpty);
  });

  test('an edit during a push stays pending', () async {
    final store = _store();
    final remote = _FakeRemote();
    remote.beforeNotebookAck = () async {
      final row = store.notebookRow(_notebookId);
      if (row != null && row.version == 1) {
        expect(row.syncState, SyncState.pending);
        await store.renameNotebook(_notebookId, 'Edited');
      }
    };
    await store.createNotebook(_notebook(), ownerId: _user);
    final status = await _service(store, remote).run();
    expect(status, isA<SyncIdle>());
    expect(remote.notebooks.single.name, 'Edited');
    expect(store.notebookRow(_notebookId)!.version, 2);
    expect(store.notebookRow(_notebookId)!.syncState, SyncState.synced);
    expect(await store.pendingNotebooks(_user), isEmpty);
  });

  test('push order is notebooks, then pages, then strokes', () async {
    final store = _store();
    final remote = _FakeRemote();
    await store.createNotebook(_notebook(page: _page()), ownerId: _user);
    await _service(store, remote).run();
    expect(remote.order, [
      SyncTables.notebooks,
      SyncTables.pages,
      SyncTables.strokes,
    ]);
  });

  test('the cursor advances only after the local write', () async {
    final store = _store();
    final remote = _FakeRemote();
    final when = DateTime.utc(2026, 9, 26);
    remote.pulledNotebooks = [
      NotebookSyncRow(
        id: _notebookId,
        name: '',
        inkColorArgb: 1,
        version: 1,
        createdAt: when,
        updatedAt: when,
        syncState: SyncState.synced,
        ownerId: _user,
      ),
    ];
    final failed = await _service(store, remote).run();
    expect(failed, isA<SyncFailed>());
    expect(await store.cursorFor(SyncTables.notebooks), isNull);

    remote.pulledNotebooks = [
      NotebookSyncRow(
        id: _notebookId,
        name: 'From cloud',
        inkColorArgb: 1,
        version: 1,
        createdAt: when,
        updatedAt: when,
        syncState: SyncState.synced,
        ownerId: _user,
      ),
    ];
    final ok = await _service(store, remote).run();
    expect(ok, isA<SyncIdle>());
    expect(
      await store.cursorFor(SyncTables.notebooks),
      SyncCursor(updatedAt: when, id: _notebookId),
    );
    expect(store.notebookRow(_notebookId)!.name, 'From cloud');
    await store.adoptUser(_user);
    expect(store.current.single.name, 'From cloud');
  });

  test('a rejected row is quarantined and the rest still sync', () async {
    final store = _store();
    final remote = _FakeRemote()..rejectNotebooks.add(_badId);
    await store.createNotebook(_notebook(empty: true), ownerId: _user);
    await store.createNotebook(
      _notebook(id: _badId, name: 'Bad', empty: true),
      ownerId: _user,
    );
    final status = await _service(store, remote).run();
    expect(status, isA<SyncIdle>());
    expect(remote.notebooks.map((row) => row.id), [_notebookId]);
    expect(store.notebookRow(_badId)!.syncState, SyncState.pending);
    expect(await store.pendingNotebooks(_user), isEmpty);
    final again = _FakeRemote();
    await _service(store, again).run();
    expect(again.notebooks, isEmpty);
  });

  test('another account is not uploaded', () async {
    final store = _store();
    final remote = _FakeRemote();
    await store.createNotebook(_notebook(name: 'Theirs'), ownerId: _other);
    await _service(store, remote, userId: _user).run();
    expect(remote.notebooks, isEmpty);
  });

  test('signing out leaves this account on screen', () async {
    final store = _store();
    await store.createNotebook(_notebook(), ownerId: _user);
    await store.createNotebook(
      _notebook(id: _otherNotebook, name: 'Theirs', empty: true),
      ownerId: _other,
    );
    await store.rememberHomeUser(_user);
    await store.adoptUser(_user);
    expect(store.current.map((notebook) => notebook.name), ['Notes']);
    await store.adoptUser(null);
    expect(store.current.map((notebook) => notebook.name), ['Notes']);
    expect(store.notebookRow(_notebookId), isNotNull);
    expect(store.notebookRow(_otherNotebook), isNotNull);
  });

  test('a push larger than one batch finishes in the same run', () async {
    final store = _store();
    final remote = _FakeRemote();
    for (var i = 0; i < 201; i++) {
      await store.createNotebook(
        _notebook(id: _batchId(i), name: 'Batch $i', empty: true),
        ownerId: _user,
      );
    }
    final status = await _service(store, remote).run();
    expect(status, isA<SyncIdle>());
    expect(remote.notebookBatchSizes, [200, 1]);
    expect(remote.notebooks, hasLength(201));
    expect(await store.pendingNotebooks(_user), isEmpty);
  });

  test('one run is shared until it finishes', () async {
    final store = _store();
    final remote = _FakeRemote();
    final gate = Completer<void>();
    remote.beforeNotebookAck = () => gate.future;
    await store.createNotebook(_notebook(), ownerId: _user);
    final service = _service(store, remote);
    final first = service.run();
    final second = service.run();
    expect(identical(first, second), isTrue);
    gate.complete();
    expect(await first, isA<SyncIdle>());
    expect(remote.upsertCalls, 1);
  });

  test('an expired session is refreshed once', () async {
    final store = _store();
    final remote = _FakeRemote()..authFailures = 1;
    final auth = _Auth(refreshResult: true);
    await store.createNotebook(_notebook(), ownerId: _user);
    final status = await SyncService(
      ledger: store,
      remote: remote,
      auth: auth,
    ).run();
    expect(status, isA<SyncIdle>());
    expect(auth.refreshes, 1);
    expect(remote.notebooks, hasLength(1));
  });

  test('a full page does not skip strokes that share its timestamp', () async {
    final store = _store();
    final remote = _FakeRemote();
    await store.createNotebook(
      _notebook(
        page: NotebookPage(
          id: _pageId,
          notebookId: _notebookId,
          pageIndex: 1,
          strokes: const [],
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ),
      ownerId: _user,
    );
    // Three upload batches. Each batch is one transaction, so every stroke
    // in it has the same server updated_at. 500 is the pull page size, so
    // the first page ends inside the third batch.
    const count = 600;
    remote.pulledStrokes = [
      for (var i = 0; i < count; i++)
        _remoteStroke(
          id: _batchId(i),
          updatedAt: DateTime.utc(2026, 9, 26, 12, i ~/ 200),
        ),
    ];

    final status = await _service(store, remote).run();
    expect(status, isA<SyncIdle>());
    await store.adoptUser(_user);
    expect(store.current.single.pages.single.strokes, hasLength(count));
    expect(remote.strokePulls, hasLength(2));
    expect(remote.strokePulls[1].after, DateTime.utc(2026, 9, 26, 12, 2));
    expect(remote.strokePulls[1].afterId, _batchId(499));
    expect(
      await store.cursorFor(SyncTables.strokes),
      SyncCursor(
        updatedAt: DateTime.utc(2026, 9, 26, 12, 2),
        id: _batchId(count - 1),
      ),
    );
  });

  test(
    'a timestamp-only cursor still reads the rows at that instant',
    () async {
      final store = _store();
      final remote = _FakeRemote();
      final tied = DateTime.utc(2026, 9, 26, 12, 2);
      await store.createNotebook(
        _notebook(
          page: NotebookPage(
            id: _pageId,
            notebookId: _notebookId,
            pageIndex: 1,
            strokes: const [],
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ),
        ownerId: _user,
      );
      await store.setCursor(SyncTables.strokes, SyncCursor(updatedAt: tied));
      remote.pulledStrokes = [
        _remoteStroke(
          id: _batchId(0),
          updatedAt: tied.subtract(const Duration(seconds: 1)),
        ),
        for (var i = 1; i <= 3; i++)
          _remoteStroke(id: _batchId(i), updatedAt: tied),
      ];

      final status = await _service(store, remote).run();
      expect(status, isA<SyncIdle>());
      await store.adoptUser(_user);
      expect(
        store.current.single.pages.single.strokes.map((stroke) => stroke.id),
        [_batchId(1), _batchId(2), _batchId(3)],
      );
      expect(remote.strokePulls.first.afterId, isNull);
    },
  );
}

StrokeSyncRow _remoteStroke({required String id, required DateTime updatedAt}) {
  return StrokeSyncRow(
    id: id,
    pageId: _pageId,
    colorArgb: 0xFF111111,
    width: 1,
    version: 1,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    syncState: SyncState.synced,
    points: Uint8List(0),
    timeOriginMs: 0,
    ownerId: _user,
  );
}

MemoryNotebookStore _store() => MemoryNotebookStore();

SyncService _service(
  MemoryNotebookStore store,
  _FakeRemote remote, {
  String userId = _user,
}) {
  return SyncService(
    ledger: store,
    remote: remote,
    auth: _Auth(id: userId),
  );
}

Notebook _notebook({
  String id = _notebookId,
  String name = 'Notes',
  NotebookPage? page,
  bool empty = false,
}) {
  return Notebook(
    id: id,
    name: name,
    inkColorArgb: 0xFF111111,
    createdAt: DateTime.utc(2026, 9, 1),
    pages: empty ? const [] : [page ?? _page()],
  );
}

NotebookPage _page() {
  return NotebookPage(
    id: _pageId,
    notebookId: _notebookId,
    pageIndex: 1,
    createdAt: DateTime.utc(2026, 9, 1),
    strokes: [
      Stroke(
        id: _strokeId,
        points: [
          StrokePoint(xMm: 1, yMm: 2, pressure: 10, touching: true, tMs: 5),
        ],
        colorArgb: 0xFF111111,
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    ],
  );
}

class _Auth implements PaperSyncAuth {
  _Auth({this.id = _user, this.refreshResult = false});

  final String id;
  final bool refreshResult;
  var refreshes = 0;

  @override
  SignedInAccount? get current => SignedInAccount(id: id);

  @override
  Stream<SignedInAccount?> watchAccount() => const Stream.empty();

  @override
  Future<void> sendEmailCode(String email) async {}

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<bool> refreshSession() async {
    refreshes += 1;
    return refreshResult;
  }

  @override
  Future<void> signOut() async {}
}

class _FakeRemote implements NotebookRemote {
  final notebooks = <NotebookSyncRow>[];
  final notebookBatchSizes = <int>[];
  final order = <String>[];
  final rejectNotebooks = <String>{};
  var failAfterWrite = 0;
  var authFailures = 0;
  var upsertCalls = 0;
  Future<void> Function()? beforeNotebookAck;
  List<NotebookSyncRow> pulledNotebooks = const [];
  List<StrokeSyncRow> pulledStrokes = const [];
  final strokePulls = <({DateTime? after, String? afterId})>[];

  @override
  Future<void> upsertNotebooks(List<NotebookSyncRow> rows) async {
    upsertCalls += 1;
    notebookBatchSizes.add(rows.length);
    if (authFailures > 0) {
      authFailures -= 1;
      throw const AuthExpired();
    }
    for (final row in rows) {
      if (rejectNotebooks.contains(row.id)) {
        throw Rejected(table: SyncTables.notebooks, id: row.id);
      }
      notebooks.removeWhere((item) => item.id == row.id);
      notebooks.add(row);
    }
    final ack = beforeNotebookAck;
    if (ack != null) await ack();
    if (failAfterWrite > 0) {
      failAfterWrite -= 1;
      throw const ServerError();
    }
    order.add(SyncTables.notebooks);
  }

  @override
  Future<void> upsertPages(List<PageSyncRow> rows) async {
    order.add(SyncTables.pages);
  }

  @override
  Future<void> upsertStrokes(List<StrokeSyncRow> rows) async {
    order.add(SyncTables.strokes);
    expect(rows.single.points, isA<Uint8List>());
    expect(rows.single.points.length, greaterThan(0));
  }

  @override
  Future<List<NotebookSyncRow>> pullNotebooks({
    DateTime? after,
    String? afterId,
    int limit = 500,
  }) async {
    final rows = pulledNotebooks;
    pulledNotebooks = const [];
    return rows;
  }

  @override
  Future<List<PageSyncRow>> pullPages({
    DateTime? after,
    String? afterId,
    int limit = 500,
  }) async {
    return const [];
  }

  @override
  Future<List<StrokeSyncRow>> pullStrokes({
    DateTime? after,
    String? afterId,
    int limit = 500,
  }) async {
    strokePulls.add((after: after, afterId: afterId));
    final rows = [...pulledStrokes]
      ..sort((a, b) {
        final byTime = a.updatedAt.compareTo(b.updatedAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    final page = [
      for (final row in rows)
        if (isAfterSyncCursor(
          updatedAt: row.updatedAt,
          id: row.id,
          after: after,
          afterId: afterId,
        ))
          row,
    ];
    if (page.length <= limit) return page;
    return page.sublist(0, limit);
  }
}
