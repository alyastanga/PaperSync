import 'dart:async';

import '../domain/ink.dart';
import '../domain/mutations.dart';
import 'points.dart';
import 'schema.dart';
import 'sync_ledger.dart';

/// The stroke being drawn, saved apart from the closed strokes.
class OpenCheckpoint {
  const OpenCheckpoint({required this.pageId, required this.stroke});

  final String pageId;
  final Stroke stroke;
}

/// Notebooks, pages, and strokes stored on the device.
///
/// A single `put` writes the record and its [SyncState] together. Deletes are
/// tombstones. The undo stack is not stored here; it lives in memory.
abstract class NotebookStore implements SyncLedger {
  List<Notebook> get current;

  Stream<List<Notebook>> watchNotebooks();

  Stream<NotebookPage?> watchPage(String id);

  Future<void> createNotebook(Notebook notebook, {String? ownerId});

  Future<void> renameNotebook(String id, String name);

  Future<void> setInkColor(String id, int inkColorArgb);

  Future<void> addPage(NotebookPage page);

  Future<void> savePage(NotebookPage page);

  Future<void> softDeletePage(String pageId, {DateTime? at});

  Future<void> upsertStroke(String pageId, Stroke stroke);

  Future<void> softDeleteStroke(String pageId, String strokeId, {DateTime? at});

  /// Writes the closed stroke, then deletes the checkpoint.
  Future<void> saveClosedStroke(String pageId, Stroke stroke);

  Future<void> writeCheckpoint(OpenCheckpoint checkpoint, {bool flush = false});

  Future<void> clearCheckpoint();

  Future<void> flush();

  Future<void> close();
}

/// Process-local store used by widget tests and as a fallback if opening
/// the boxes throws.
class MemoryNotebookStore implements NotebookStore {
  MemoryNotebookStore({List<Notebook> notebooks = const []})
    : _notebooks = [...notebooks];

  final List<Notebook> _notebooks;
  final Map<String, String?> _owners = {};
  final StreamController<List<Notebook>> _updates =
      StreamController<List<Notebook>>.broadcast();
  String? _currentUserId;
  String? _homeUserId;
  bool _closed = false;

  /// Rows whose owner is neither null nor [userId] stay out of [current].
  set currentUserId(String? userId) => _currentUserId = userId;

  final Map<String, DateTime> _cursors = {};
  final Set<String> _quarantine = {};
  final Map<String, DateTime> _tombstoneSyncedAt = {};

  @override
  List<Notebook> get current => List<Notebook>.unmodifiable(
    _notebooks
        .where((notebook) {
          return !notebook.isDeleted && _visible(_owners[notebook.id]);
        })
        .map((notebook) {
          final pages = [
            for (final page in notebook.pages)
              if (!page.isDeleted) page,
          ];
          if (pages.length == notebook.pages.length) return notebook;
          return notebook.copyWith(pages: pages, updatedAt: notebook.updatedAt);
        }),
  );

  @override
  Stream<List<Notebook>> watchNotebooks() async* {
    yield current;
    yield* _updates.stream;
  }

  @override
  Stream<NotebookPage?> watchPage(String id) {
    return watchNotebooks().map((notebooks) => _findPage(notebooks, id));
  }

  @override
  Future<void> createNotebook(Notebook notebook, {String? ownerId}) async {
    final saved = notebook.copyWith(syncState: SyncState.pending);
    _owners[saved.id] = ownerId;
    _notebooks.insert(0, saved);
    _emit();
  }

  @override
  Future<void> renameNotebook(String id, String name) async {
    _replaceNotebook(id, (notebook) {
      return notebook.copyWith(
        name: name,
        syncState: SyncState.pending,
        updatedAt: DateTime.now(),
        version: notebook.version + 1,
      );
    });
  }

  @override
  Future<void> setInkColor(String id, int inkColorArgb) async {
    _replaceNotebook(id, (notebook) {
      return notebook.copyWith(
        inkColorArgb: inkColorArgb,
        syncState: SyncState.pending,
        updatedAt: DateTime.now(),
        version: notebook.version + 1,
      );
    });
  }

  @override
  Future<void> addPage(NotebookPage page) async {
    _replaceNotebook(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [...notebook.pages, page],
        syncState: SyncState.pending,
      );
    });
  }

  @override
  Future<void> savePage(NotebookPage page) async {
    final saved = page.copyWith(
      syncState: SyncState.pending,
      version: page.version + 1,
      updatedAt: DateTime.now(),
    );
    _replaceNotebook(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [
          for (final current in notebook.pages)
            if (current.id == page.id) saved else current,
        ],
        syncState: SyncState.pending,
      );
    });
  }

  @override
  Future<void> softDeletePage(String pageId, {DateTime? at}) async {
    final when = at ?? DateTime.now();
    for (var i = 0; i < _notebooks.length; i++) {
      final notebook = _notebooks[i];
      if (!notebook.pages.any((page) => page.id == pageId)) continue;
      _notebooks[i] = notebook.copyWith(
        pages: [
          for (final page in notebook.pages)
            if (page.id != pageId)
              page
            else
              page.copyWith(
                deletedAt: when,
                updatedAt: when,
                version: page.version + 1,
                syncState: SyncState.pending,
              ),
        ],
        syncState: SyncState.pending,
        updatedAt: when,
      );
      _emit();
      return;
    }
  }

  @override
  Future<void> upsertStroke(String pageId, Stroke stroke) async {
    final saved = stroke.copyWith(syncState: SyncState.pending);
    _replacePage(pageId, (page) {
      final exists = page.strokes.any((item) => item.id == saved.id);
      final strokes = [
        for (final item in page.strokes)
          if (item.id == saved.id) saved else item,
        if (!exists) saved,
      ];
      return page.copyWith(strokes: strokes, syncState: SyncState.pending);
    });
  }

  @override
  Future<void> softDeleteStroke(
    String pageId,
    String strokeId, {
    DateTime? at,
  }) async {
    final page = _page(pageId);
    if (page == null) return;
    for (final stroke in page.strokes) {
      if (stroke.id == strokeId && stroke.deletedAt == null) {
        await upsertStroke(pageId, stroke.erased(at: at));
        return;
      }
    }
  }

  @override
  Future<void> saveClosedStroke(String pageId, Stroke stroke) async {
    await upsertStroke(pageId, stroke);
    await clearCheckpoint();
  }

  @override
  Future<void> writeCheckpoint(
    OpenCheckpoint checkpoint, {
    bool flush = false,
  }) async {}

  @override
  Future<void> clearCheckpoint() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _updates.close();
  }

  @override
  Future<void> adoptUser(String? userId) async {
    _currentUserId = userId;
    _emit();
  }

  @override
  Future<void> claimUnowned(String userId) async {
    for (final notebook in _notebooks) {
      if (_owners[notebook.id] == null) _owners[notebook.id] = userId;
    }
    _emit();
  }

  @override
  Future<void> rememberHomeUser(String userId) async {
    _homeUserId = userId;
    _emit();
  }

  @override
  Future<List<NotebookSyncRow>> pendingNotebooks(
    String userId, {
    int limit = 200,
  }) async {
    final rows = [
      for (final notebook in _notebooks)
        if (_canUpload(
          userId,
          _owners[notebook.id],
          notebook.syncState,
          SyncTables.notebooks,
          notebook.id,
        ))
          _notebookRow(notebook),
    ]..sort((a, b) => a.id.compareTo(b.id));
    if (rows.length <= limit) return rows;
    return rows.sublist(0, limit);
  }

  @override
  Future<List<PageSyncRow>> pendingPages(
    String userId, {
    int limit = 200,
  }) async {
    final rows = <PageSyncRow>[];
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (_canUpload(
          userId,
          _owners[notebook.id],
          page.syncState,
          SyncTables.pages,
          page.id,
        )) {
          rows.add(_pageRow(notebook, page));
        }
      }
    }
    rows.sort((a, b) => a.id.compareTo(b.id));
    if (rows.length <= limit) return rows;
    return rows.sublist(0, limit);
  }

  @override
  Future<List<StrokeSyncRow>> pendingStrokes(
    String userId, {
    int limit = 200,
  }) async {
    final rows = <StrokeSyncRow>[];
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        for (final stroke in page.strokes) {
          if (_canUpload(
            userId,
            _owners[notebook.id],
            stroke.syncState,
            SyncTables.strokes,
            stroke.id,
          )) {
            rows.add(_strokeRow(page.id, stroke, _owners[notebook.id]));
          }
        }
      }
    }
    rows.sort((a, b) => a.id.compareTo(b.id));
    if (rows.length <= limit) return rows;
    return rows.sublist(0, limit);
  }

  @override
  NotebookSyncRow? notebookRow(String id) {
    for (final notebook in _notebooks) {
      if (notebook.id == id) return _notebookRow(notebook);
    }
    return null;
  }

  @override
  PageSyncRow? pageRow(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (page.id == id) return _pageRow(notebook, page);
      }
    }
    return null;
  }

  @override
  StrokeSyncRow? strokeRow(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        for (final stroke in page.strokes) {
          if (stroke.id == id) {
            return _strokeRow(page.id, stroke, _owners[notebook.id]);
          }
        }
      }
    }
    return null;
  }

  @override
  Future<bool> markNotebookSynced(String id, int version) async {
    for (final notebook in _notebooks) {
      if (notebook.id != id) continue;
      if (notebook.version != version) return false;
      _replaceNotebook(id, (current) {
        return current.copyWith(syncState: SyncState.synced);
      });
      if (notebook.isDeleted) {
        _tombstoneSyncedAt['${SyncTables.notebooks}:$id'] = DateTime.now();
      }
      return true;
    }
    return false;
  }

  @override
  Future<bool> markPageSynced(String id, int version) async {
    final page = _pageAnywhere(id);
    if (page == null || page.version != version) return false;
    _replacePage(id, (current) {
      return current.copyWith(syncState: SyncState.synced);
    });
    if (page.isDeleted) {
      _tombstoneSyncedAt['${SyncTables.pages}:$id'] = DateTime.now();
    }
    return true;
  }

  @override
  Future<bool> markStrokeSynced(String id, int version) async {
    final stroke = _strokeAnywhere(id);
    if (stroke == null || stroke.version != version) return false;
    _replacePage(_pageIdOfStroke(id)!, (page) {
      return page.copyWith(
        strokes: [
          for (final item in page.strokes)
            if (item.id == id)
              item.copyWith(syncState: SyncState.synced)
            else
              item,
        ],
        syncState: page.syncState,
      );
    });
    if (stroke.isDeleted) {
      _tombstoneSyncedAt['${SyncTables.strokes}:$id'] = DateTime.now();
    }
    return true;
  }

  @override
  Future<void> applyNotebook(NotebookSyncRow row) async {
    final existing = _notebookById(row.id);
    final notebook = Notebook(
      id: row.id,
      name: row.name,
      pages: existing?.pages ?? const [],
      inkColorArgb: row.inkColorArgb,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      syncState: SyncState.synced,
      version: row.version,
    );
    final index = _notebooks.indexWhere((item) => item.id == row.id);
    if (index >= 0) {
      _notebooks[index] = notebook;
    } else {
      _notebooks.insert(0, notebook);
    }
    _owners[row.id] = row.ownerId ?? _owners[row.id] ?? _currentUserId;
    if (row.isDeleted) {
      _tombstoneSyncedAt['${SyncTables.notebooks}:${row.id}'] = DateTime.now();
    }
    _emit();
  }

  @override
  Future<void> applyPage(PageSyncRow row) async {
    final notebook = _notebookById(row.notebookId);
    if (notebook == null) return;
    final existing = _pageAnywhere(row.id);
    final page = NotebookPage(
      id: row.id,
      notebookId: row.notebookId,
      pageIndex: row.pageIndex,
      strokes: existing?.strokes ?? const [],
      createdAt: row.createdAt,
      capturedAt: row.capturedAt,
      updatedAt: row.updatedAt,
      paperRect: row.paperRect,
      recognizedText: existing?.recognizedText ?? row.recognizedText,
      markers: existing?.markers ?? row.markers,
      deletedAt: row.deletedAt,
      syncState: SyncState.synced,
      version: row.version,
    );
    final pages = [
      for (final item in notebook.pages)
        if (item.id != row.id) item,
      page,
    ];
    _replaceNotebook(notebook.id, (current) {
      return current.copyWith(pages: pages, updatedAt: current.updatedAt);
    });
    if (row.isDeleted) {
      _tombstoneSyncedAt['${SyncTables.pages}:${row.id}'] = DateTime.now();
    }
  }

  @override
  Future<void> applyStroke(StrokeSyncRow row) async {
    final pageId = row.pageId;
    if (_pageAnywhere(pageId) == null) return;
    final packed = unpackPoints(row.points, row.timeOriginMs);
    final stroke = Stroke(
      id: row.id,
      points: packed,
      colorArgb: row.colorArgb,
      width: row.width,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deletedAt: row.deletedAt,
      syncState: SyncState.synced,
    );
    _replacePage(pageId, (page) {
      final strokes = [
        for (final item in page.strokes)
          if (item.id != stroke.id) item,
        stroke,
      ];
      return page.copyWith(strokes: strokes, syncState: page.syncState);
    });
    if (row.isDeleted) {
      _tombstoneSyncedAt['${SyncTables.strokes}:${row.id}'] = DateTime.now();
    }
  }

  @override
  Future<DateTime?> cursorFor(String table) async => _cursors[table];

  @override
  Future<void> setCursor(String table, DateTime cursor) async {
    _cursors[table] = cursor;
  }

  @override
  Future<void> quarantine(String table, String id) async {
    _quarantine.add('$table:$id');
  }

  @override
  Future<int> purgeSyncedTombstones({required DateTime syncedBefore}) async {
    var removed = 0;
    for (var i = 0; i < _notebooks.length; i++) {
      final notebook = _notebooks[i];
      final notebookKey = '${SyncTables.notebooks}:${notebook.id}';
      final dropNotebook =
          notebook.isDeleted &&
          notebook.syncState == SyncState.synced &&
          _syncedBefore(notebookKey, notebook.deletedAt, syncedBefore);
      if (dropNotebook) {
        _notebooks.removeAt(i);
        _owners.remove(notebook.id);
        _tombstoneSyncedAt.remove(notebookKey);
        removed += 1;
        i -= 1;
        continue;
      }
      final pages = <NotebookPage>[];
      for (final page in notebook.pages) {
        final pageKey = '${SyncTables.pages}:${page.id}';
        final dropPage =
            page.isDeleted &&
            page.syncState == SyncState.synced &&
            _syncedBefore(pageKey, page.deletedAt, syncedBefore);
        if (dropPage) {
          _tombstoneSyncedAt.remove(pageKey);
          removed += 1;
          continue;
        }
        final strokes = <Stroke>[];
        for (final stroke in page.strokes) {
          final strokeKey = '${SyncTables.strokes}:${stroke.id}';
          final dropStroke =
              stroke.isDeleted &&
              stroke.syncState == SyncState.synced &&
              _syncedBefore(strokeKey, stroke.deletedAt, syncedBefore);
          if (dropStroke) {
            _tombstoneSyncedAt.remove(strokeKey);
            removed += 1;
            continue;
          }
          strokes.add(stroke);
        }
        pages.add(
          strokes.length == page.strokes.length
              ? page
              : page.copyWith(strokes: strokes, syncState: page.syncState),
        );
      }
      _notebooks[i] = pages.length == notebook.pages.length
          ? notebook
          : notebook.copyWith(pages: pages, updatedAt: notebook.updatedAt);
    }
    if (removed > 0) _emit();
    return removed;
  }

  bool _canUpload(
    String userId,
    String? ownerId,
    SyncState syncState,
    String table,
    String id,
  ) {
    return ownerId == userId &&
        syncState == SyncState.pending &&
        !_quarantine.contains('$table:$id');
  }

  bool _syncedBefore(String key, DateTime? deletedAt, DateTime cutoff) {
    final stamped = _tombstoneSyncedAt[key] ?? deletedAt;
    if (stamped == null) return false;
    return stamped.isBefore(cutoff);
  }

  Notebook? _notebookById(String id) {
    for (final notebook in _notebooks) {
      if (notebook.id == id) return notebook;
    }
    return null;
  }

  NotebookPage? _pageAnywhere(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (page.id == id) return page;
      }
    }
    return null;
  }

  Stroke? _strokeAnywhere(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        for (final stroke in page.strokes) {
          if (stroke.id == id) return stroke;
        }
      }
    }
    return null;
  }

  String? _pageIdOfStroke(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        for (final stroke in page.strokes) {
          if (stroke.id == id) return page.id;
        }
      }
    }
    return null;
  }

  NotebookSyncRow _notebookRow(Notebook notebook) {
    return NotebookSyncRow(
      id: notebook.id,
      name: notebook.name,
      inkColorArgb: notebook.inkColorArgb,
      version: notebook.version,
      createdAt: notebook.createdAt,
      updatedAt: notebook.updatedAt,
      deletedAt: notebook.deletedAt,
      syncState: notebook.syncState,
      ownerId: _owners[notebook.id],
    );
  }

  PageSyncRow _pageRow(Notebook notebook, NotebookPage page) {
    return PageSyncRow(
      id: page.id,
      notebookId: page.notebookId,
      pageIndex: page.pageIndex,
      paperLeft: page.paperRect.leftMm,
      paperTop: page.paperRect.topMm,
      paperWidth: page.paperRect.widthMm,
      paperHeight: page.paperRect.heightMm,
      recognizedText: page.recognizedText,
      markers: page.markers,
      version: page.version,
      createdAt: page.createdAt,
      capturedAt: page.capturedAt,
      updatedAt: page.updatedAt,
      deletedAt: page.deletedAt,
      syncState: page.syncState,
      ownerId: _owners[notebook.id],
    );
  }

  StrokeSyncRow _strokeRow(String pageId, Stroke stroke, String? ownerId) {
    final packed = packPoints(stroke.points);
    return StrokeSyncRow(
      id: stroke.id,
      pageId: pageId,
      colorArgb: stroke.colorArgb,
      width: stroke.width,
      version: stroke.version,
      createdAt: stroke.createdAt,
      updatedAt: stroke.updatedAt,
      deletedAt: stroke.deletedAt,
      syncState: stroke.syncState,
      ownerId: ownerId,
      points: packed.bytes,
      timeOriginMs: packed.timeOriginMs,
    );
  }

  void _replaceNotebook(
    String id,
    Notebook Function(Notebook notebook) update,
  ) {
    for (var i = 0; i < _notebooks.length; i++) {
      if (_notebooks[i].id != id) continue;
      _notebooks[i] = update(_notebooks[i]);
      _emit();
      return;
    }
  }

  void _replacePage(
    String pageId,
    NotebookPage Function(NotebookPage page) update,
  ) {
    for (var i = 0; i < _notebooks.length; i++) {
      final notebook = _notebooks[i];
      if (!notebook.pages.any((page) => page.id == pageId)) continue;
      _notebooks[i] = notebook.copyWith(
        pages: [
          for (final page in notebook.pages)
            if (page.id == pageId) update(page) else page,
        ],
      );
      _emit();
      return;
    }
  }

  NotebookPage? _page(String id) => _findPage(_notebooks, id);

  void _emit() {
    if (_closed || _updates.isClosed) return;
    _updates.add(current);
  }

  bool _visible(String? ownerId) {
    if (ownerId == null || ownerId == _currentUserId) return true;
    return _currentUserId == null && ownerId == _homeUserId;
  }
}

NotebookPage? _findPage(List<Notebook> notebooks, String id) {
  for (final notebook in notebooks) {
    for (final page in notebook.pages) {
      if (page.id == id) return page;
    }
  }
  return null;
}
