import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

import '../domain/ink.dart';
import '../domain/mutations.dart';
import 'notebook_store.dart';
import 'points.dart';
import 'records.dart';
import 'schema.dart';
import 'sync_ledger.dart';

/// Hive-backed notebooks. Cache updates are synchronous; disk writes are queued.
class HiveNotebookStore implements NotebookStore {
  HiveNotebookStore({
    required Box<StoredNotebook> notebooks,
    required Box<StoredPage> pages,
    required Box<StoredStroke> strokes,
    required Box<StoredCheckpoint> checkpoint,
    required Box<Object> meta,
    required this.currentUserId,
    this.debounce = const Duration(milliseconds: 50),
  }) : _notebooksBox = notebooks,
       _pagesBox = pages,
       _strokesBox = strokes,
       _checkpointBox = checkpoint,
       _metaBox = meta {
    final savedHome = meta.get(MetaKeys.homeUserId);
    if (savedHome is String && savedHome.isNotEmpty) {
      _homeUserId = savedHome;
    }
    _load();
  }

  final Box<StoredNotebook> _notebooksBox;
  final Box<StoredPage> _pagesBox;
  final Box<StoredStroke> _strokesBox;
  final Box<StoredCheckpoint> _checkpointBox;
  final Box<Object> _metaBox;
  String? currentUserId;
  String? _homeUserId;
  final Duration debounce;

  final List<Notebook> _notebooks = [];
  final StreamController<List<Notebook>> _updates =
      StreamController<List<Notebook>>.broadcast();
  Timer? _debounceTimer;
  Future<void> _pending = Future<void>.value();
  bool _closed = false;

  @override
  List<Notebook> get current {
    final visible = [..._notebooks];
    visible.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return List<Notebook>.unmodifiable(visible);
  }

  @override
  Stream<List<Notebook>> watchNotebooks() async* {
    yield current;
    yield* _updates.stream;
  }

  @override
  Stream<NotebookPage?> watchPage(String id) {
    return watchNotebooks().map((notebooks) {
      for (final notebook in notebooks) {
        for (final page in notebook.pages) {
          if (page.id == id) return page;
        }
      }
      return null;
    });
  }

  @override
  Future<void> createNotebook(Notebook notebook, {String? ownerId}) {
    final saved = notebook.copyWith(syncState: SyncState.pending);
    if (_owns(ownerId)) {
      _notebooks.insert(0, saved);
      _emit();
    }
    return _enqueue(() async {
      await _notebooksBox.put(
        saved.id,
        StoredNotebook.fromDomain(saved, ownerId: ownerId),
      );
      for (final page in saved.pages) {
        await _writePageRecord(page, ownerId: ownerId);
        for (final stroke in page.strokes) {
          await _strokesBox.put(
            stroke.id,
            StoredStroke.fromDomain(page.id, stroke, ownerId: ownerId),
          );
        }
      }
      await _notebooksBox.flush();
      await _pagesBox.flush();
      await _strokesBox.flush();
    });
  }

  @override
  Future<void> renameNotebook(String id, String name) {
    final now = DateTime.now();
    _replace(id, (notebook) {
      return notebook.copyWith(
        name: name,
        syncState: SyncState.pending,
        updatedAt: now,
        version: notebook.version + 1,
      );
    });
    return _enqueue(() => _putNotebook(id));
  }

  @override
  Future<void> setInkColor(String id, int inkColorArgb) {
    final now = DateTime.now();
    _replace(id, (notebook) {
      return notebook.copyWith(
        inkColorArgb: inkColorArgb,
        syncState: SyncState.pending,
        updatedAt: now,
        version: notebook.version + 1,
      );
    });
    return _enqueue(() => _putNotebook(id));
  }

  @override
  Future<void> addPage(NotebookPage page) {
    final saved = page.copyWith(syncState: SyncState.pending);
    _replace(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [...notebook.pages, saved],
        syncState: SyncState.pending,
      );
    });
    return _enqueue(() async {
      await _writePageRecord(saved);
      for (final stroke in saved.strokes) {
        await _strokesBox.put(
          stroke.id,
          StoredStroke.fromDomain(saved.id, stroke),
        );
      }
      await _putNotebook(page.notebookId);
      await _pagesBox.flush();
    });
  }

  @override
  Future<void> savePage(NotebookPage page) {
    final saved = page.copyWith(
      syncState: SyncState.pending,
      version: page.version + 1,
      updatedAt: DateTime.now(),
    );
    _replace(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [
          for (final current in notebook.pages)
            if (current.id == page.id) saved else current,
        ],
        syncState: SyncState.pending,
      );
    });
    return _enqueue(() async {
      await _writePageRecord(saved);
      await _pagesBox.flush();
    });
  }

  @override
  Future<void> softDeletePage(String pageId, {DateTime? at}) {
    final when = at ?? DateTime.now();
    String? notebookId;
    for (final notebook in _notebooks) {
      if (notebook.pages.any((page) => page.id == pageId)) {
        notebookId = notebook.id;
      }
    }
    if (notebookId != null) {
      _replace(notebookId, (notebook) {
        return notebook.copyWith(
          pages: [
            for (final page in notebook.pages)
              if (page.id != pageId) page,
          ],
          syncState: SyncState.pending,
          updatedAt: when,
        );
      });
    }
    return _enqueue(() async {
      final existing = _pagesBox.get(pageId);
      if (existing != null) {
        await _pagesBox.put(
          pageId,
          existing.copyWith(
            deletedAtUs: when.microsecondsSinceEpoch,
            syncState: 0,
            version: existing.version + 1,
            updatedAtUs: when.microsecondsSinceEpoch,
          ),
        );
        await _pagesBox.flush();
      }
      final owner = notebookId;
      if (owner != null) await _putNotebook(owner);
    });
  }

  @override
  Future<void> upsertStroke(String pageId, Stroke stroke) {
    final saved = stroke.copyWith(syncState: SyncState.pending);
    _putStrokeInCache(pageId, saved);
    return _enqueue(() => _writeStroke(pageId, saved));
  }

  @override
  Future<void> softDeleteStroke(
    String pageId,
    String strokeId, {
    DateTime? at,
  }) {
    final page = _page(pageId);
    if (page == null) return Future<void>.value();
    for (final stroke in page.strokes) {
      if (stroke.id == strokeId && !stroke.isDeleted) {
        return upsertStroke(pageId, stroke.erased(at: at));
      }
    }
    return Future<void>.value();
  }

  @override
  Future<void> saveClosedStroke(String pageId, Stroke stroke) {
    final saved = stroke.copyWith(syncState: SyncState.pending);
    _putStrokeInCache(pageId, saved);
    return _enqueue(() async {
      await _writeStroke(pageId, saved);
      await _checkpointBox.delete(CheckpointKeys.open);
      await _strokesBox.flush();
      await _checkpointBox.flush();
    });
  }

  @override
  Future<void> writeCheckpoint(
    OpenCheckpoint checkpoint, {
    bool flush = false,
  }) {
    return _enqueue(() async {
      await _checkpointBox.put(
        CheckpointKeys.open,
        StoredCheckpoint.fromStroke(checkpoint.pageId, checkpoint.stroke),
      );
      if (flush) await _checkpointBox.flush();
    });
  }

  @override
  Future<void> clearCheckpoint() {
    return _enqueue(() async {
      await _checkpointBox.delete(CheckpointKeys.open);
      await _checkpointBox.flush();
    });
  }

  @override
  Future<void> flush() {
    return _enqueue(() async {
      await _notebooksBox.flush();
      await _pagesBox.flush();
      await _strokesBox.flush();
      await _checkpointBox.flush();
      await _metaBox.flush();
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _debounceTimer?.cancel();
    await _pending;
    await _notebooksBox.flush();
    await _pagesBox.flush();
    await _strokesBox.flush();
    await _checkpointBox.flush();
    await _metaBox.flush();
    await _notebooksBox.close();
    await _pagesBox.close();
    await _strokesBox.close();
    await _checkpointBox.close();
    await _metaBox.close();
    await _updates.close();
  }

  void _load() {
    _notebooks.clear();
    for (final key in _notebooksBox.keys) {
      final stored = _notebooksBox.get(key);
      if (stored == null || stored.deletedAtUs != null) continue;
      if (!_owns(stored.ownerId)) continue;
      try {
        _notebooks.add(_notebookFrom(stored));
      } on ArgumentError {
        // Keep the record on disk and out of the library.
      }
    }
  }

  Notebook _notebookFrom(StoredNotebook stored) {
    final pages = <NotebookPage>[];
    for (final key in _pagesBox.keys) {
      final page = _pagesBox.get(key);
      if (page == null) continue;
      if (page.notebookId != stored.id || page.deletedAtUs != null) continue;
      if (!_owns(page.ownerId)) continue;
      pages.add(_pageFrom(page));
    }
    pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return Notebook(
      id: stored.id,
      name: stored.name,
      pages: pages,
      inkColorArgb: stored.inkColorArgb,
      createdAt: clockTime(
        stored.createdAtUs,
        stored.clockFlags,
        clockCreatedUtc,
      ),
      updatedAt: clockTime(
        stored.updatedAtUs,
        stored.clockFlags,
        clockUpdatedUtc,
      ),
      syncState: stored.syncState == 1 ? SyncState.synced : SyncState.pending,
      version: stored.version < 1 ? 1 : stored.version,
    );
  }

  NotebookPage _pageFrom(StoredPage stored) {
    final strokes = <Stroke>[];
    for (final key in _strokesBox.keys) {
      final stroke = _strokesBox.get(key);
      if (stroke == null || stroke.pageId != stored.id) continue;
      if (!_owns(stroke.ownerId)) continue;
      strokes.add(stroke.toDomain());
    }
    return NotebookPage(
      id: stored.id,
      notebookId: stored.notebookId,
      pageIndex: stored.pageIndex,
      strokes: strokes,
      createdAt: clockTime(
        stored.createdAtUs,
        stored.clockFlags,
        clockCreatedUtc,
      ),
      capturedAt: clockTime(
        stored.capturedAtUs,
        stored.clockFlags,
        clockCapturedUtc,
      ),
      paperRect: PaperRect(
        leftMm: stored.paperLeft,
        topMm: stored.paperTop,
        widthMm: stored.paperWidth,
        heightMm: stored.paperHeight,
      ),
      recognizedText: stored.recognizedText,
      markers: stored.markers,
      syncState: stored.syncState == 1 ? SyncState.synced : SyncState.pending,
      version: stored.version < 1 ? 1 : stored.version,
      updatedAt: stored.updatedAtUs == 0
          ? clockTime(stored.capturedAtUs, stored.clockFlags, clockCapturedUtc)
          : clockTime(stored.updatedAtUs, stored.clockFlags, clockUpdatedUtc),
    );
  }

  Future<void> _writePageRecord(NotebookPage page, {String? ownerId}) {
    return _pagesBox.put(
      page.id,
      StoredPage.fromDomain(page, ownerId: ownerId ?? _pageOwner(page.id)),
    );
  }

  Future<void> _writeStroke(String pageId, Stroke stroke) async {
    await _strokesBox.put(
      stroke.id,
      StoredStroke.fromDomain(
        pageId,
        stroke,
        ownerId:
            _strokesBox.get(stroke.id)?.ownerId ??
            _pageOwner(pageId) ??
            currentUserId,
      ),
    );
    await _putNotebook(_notebookIdForPage(pageId));
    await _strokesBox.flush();
  }

  Future<void> _putNotebook(String? id) async {
    if (id == null) return;
    final notebook = _notebookById(id);
    if (notebook == null) return;
    await _notebooksBox.put(
      id,
      StoredNotebook.fromDomain(notebook, ownerId: _notebookOwner(id)),
    );
    await _notebooksBox.flush();
  }

  void _putStrokeInCache(String pageId, Stroke stroke) {
    _replace(_notebookIdForPage(pageId), (notebook) {
      return notebook.copyWith(
        pages: [
          for (final page in notebook.pages)
            if (page.id != pageId)
              page
            else
              page.copyWith(
                strokes: _replacedStrokes(page.strokes, stroke),
                syncState: SyncState.pending,
              ),
        ],
        syncState: SyncState.pending,
      );
    });
  }

  String? _notebookIdForPage(String pageId) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (page.id == pageId) return notebook.id;
      }
    }
    final stored = _pagesBox.get(pageId);
    return stored?.notebookId;
  }

  Notebook? _notebookById(String id) {
    for (final notebook in _notebooks) {
      if (notebook.id == id) return notebook;
    }
    return null;
  }

  NotebookPage? _page(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (page.id == id) return page;
      }
    }
    return null;
  }

  String? _notebookOwner(String id) => _notebooksBox.get(id)?.ownerId;

  String? _pageOwner(String id) => _pagesBox.get(id)?.ownerId;

  void _replace(String? id, Notebook Function(Notebook notebook) update) {
    if (id == null) return;
    for (var i = 0; i < _notebooks.length; i++) {
      if (_notebooks[i].id != id) continue;
      _notebooks[i] = update(_notebooks[i]);
      _emit();
      return;
    }
  }

  void _emit() {
    if (_closed || _updates.isClosed) return;
    if (debounce == Duration.zero) {
      _updates.add(current);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (_closed || _updates.isClosed) return;
      _updates.add(current);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _pending = _pending
        .then((_) async {
          try {
            done.complete(await action());
          } catch (error, stack) {
            done.completeError(error, stack);
          }
        })
        .catchError((Object _) {});
    return done.future;
  }

  bool _owns(String? ownerId) {
    if (ownerId == null || ownerId == currentUserId) return true;
    return currentUserId == null && ownerId == _homeUserId;
  }

  @override
  Future<void> rememberHomeUser(String userId) {
    return _enqueue(() async {
      _homeUserId = userId;
      await _metaBox.put(MetaKeys.homeUserId, userId);
      await _metaBox.flush();
      _load();
      _emit();
    });
  }

  @override
  Future<void> adoptUser(String? userId) {
    return _enqueue(() async {
      currentUserId = userId;
      _load();
      _emit();
    });
  }

  @override
  Future<void> claimUnowned(String userId) {
    return _enqueue(() async {
      for (final key in _notebooksBox.keys) {
        final stored = _notebooksBox.get(key);
        if (stored != null && stored.ownerId == null) {
          await _notebooksBox.put(key, stored.copyWith(ownerId: userId));
        }
      }
      for (final key in _pagesBox.keys) {
        final stored = _pagesBox.get(key);
        if (stored != null && stored.ownerId == null) {
          await _pagesBox.put(key, stored.copyWith(ownerId: userId));
        }
      }
      for (final key in _strokesBox.keys) {
        final stored = _strokesBox.get(key);
        if (stored != null && stored.ownerId == null) {
          await _strokesBox.put(
            key,
            StoredStroke(
              id: stored.id,
              pageId: stored.pageId,
              colorArgb: stored.colorArgb,
              width: stored.width,
              createdAtUs: stored.createdAtUs,
              updatedAtUs: stored.updatedAtUs,
              version: stored.version,
              deletedAtUs: stored.deletedAtUs,
              syncState: stored.syncState,
              ownerId: userId,
              packedPoints: stored.packedPoints,
              timeOriginMs: stored.timeOriginMs,
              legacyPoints: stored.legacyPoints,
              clockFlags: stored.clockFlags,
            ),
          );
        }
      }
      await _notebooksBox.flush();
      await _pagesBox.flush();
      await _strokesBox.flush();
      _load();
      _emit();
    });
  }

  @override
  Future<List<NotebookSyncRow>> pendingNotebooks(
    String userId, {
    int limit = 200,
  }) {
    return _enqueue(() async {
      final rows = <NotebookSyncRow>[];
      for (final key in _notebooksBox.keys) {
        final stored = _notebooksBox.get(key);
        if (stored == null ||
            !_uploadable(
              stored.ownerId,
              userId,
              stored.syncState,
              SyncTables.notebooks,
              stored.id,
            )) {
          continue;
        }
        rows.add(_notebookSyncRow(stored));
      }
      rows.sort((a, b) => a.id.compareTo(b.id));
      if (rows.length <= limit) return rows;
      return rows.sublist(0, limit);
    });
  }

  @override
  Future<List<PageSyncRow>> pendingPages(String userId, {int limit = 200}) {
    return _enqueue(() async {
      final rows = <PageSyncRow>[];
      for (final key in _pagesBox.keys) {
        final stored = _pagesBox.get(key);
        if (stored == null ||
            !_uploadable(
              stored.ownerId,
              userId,
              stored.syncState,
              SyncTables.pages,
              stored.id,
            )) {
          continue;
        }
        rows.add(_pageSyncRow(stored));
      }
      rows.sort((a, b) => a.id.compareTo(b.id));
      if (rows.length <= limit) return rows;
      return rows.sublist(0, limit);
    });
  }

  @override
  Future<List<StrokeSyncRow>> pendingStrokes(String userId, {int limit = 200}) {
    return _enqueue(() async {
      final rows = <StrokeSyncRow>[];
      for (final key in _strokesBox.keys) {
        final stored = _strokesBox.get(key);
        if (stored == null ||
            !_uploadable(
              stored.ownerId,
              userId,
              stored.syncState,
              SyncTables.strokes,
              stored.id,
            )) {
          continue;
        }
        rows.add(_strokeSyncRow(stored));
      }
      rows.sort((a, b) => a.id.compareTo(b.id));
      if (rows.length <= limit) return rows;
      return rows.sublist(0, limit);
    });
  }

  @override
  NotebookSyncRow? notebookRow(String id) {
    final stored = _notebooksBox.get(id);
    if (stored == null) return null;
    return _notebookSyncRow(stored);
  }

  @override
  PageSyncRow? pageRow(String id) {
    final stored = _pagesBox.get(id);
    if (stored == null) return null;
    return _pageSyncRow(stored);
  }

  @override
  StrokeSyncRow? strokeRow(String id) {
    final stored = _strokesBox.get(id);
    if (stored == null) return null;
    return _strokeSyncRow(stored);
  }

  @override
  Future<bool> markNotebookSynced(String id, int version) {
    final cached = _notebookById(id);
    if (cached != null && cached.version != version) {
      return Future<bool>.value(false);
    }
    return _enqueue(() async {
      final stored = _notebooksBox.get(id);
      if (stored == null || stored.version != version) return false;
      await _notebooksBox.put(id, stored.copyWith(syncState: 1));
      await _notebooksBox.flush();
      if (stored.deletedAtUs != null) await _stampTombstone(id);
      _replace(id, (notebook) {
        if (notebook.version != version) return notebook;
        return notebook.copyWith(syncState: SyncState.synced);
      });
      return true;
    });
  }

  @override
  Future<bool> markPageSynced(String id, int version) {
    return _enqueue(() async {
      final stored = _pagesBox.get(id);
      if (stored == null || stored.version != version) return false;
      await _pagesBox.put(id, stored.copyWith(syncState: 1));
      await _pagesBox.flush();
      if (stored.deletedAtUs != null) await _stampTombstone(id);
      _load();
      _emit();
      return true;
    });
  }

  @override
  Future<bool> markStrokeSynced(String id, int version) {
    final pageId = _pageIdOfCachedStroke(id);
    if (pageId != null) {
      final page = _page(pageId);
      final stroke = page?.strokes.where((item) => item.id == id);
      if (stroke != null &&
          stroke.isNotEmpty &&
          stroke.first.version != version) {
        return Future<bool>.value(false);
      }
    }
    return _enqueue(() async {
      final stored = _strokesBox.get(id);
      if (stored == null || stored.version != version) return false;
      await _strokesBox.put(
        id,
        StoredStroke(
          id: stored.id,
          pageId: stored.pageId,
          colorArgb: stored.colorArgb,
          width: stored.width,
          createdAtUs: stored.createdAtUs,
          updatedAtUs: stored.updatedAtUs,
          version: stored.version,
          deletedAtUs: stored.deletedAtUs,
          syncState: 1,
          ownerId: stored.ownerId,
          packedPoints: stored.packedPoints,
          timeOriginMs: stored.timeOriginMs,
          legacyPoints: stored.legacyPoints,
          clockFlags: stored.clockFlags,
        ),
      );
      await _strokesBox.flush();
      if (stored.deletedAtUs != null) await _stampTombstone(id);
      _load();
      _emit();
      return true;
    });
  }

  @override
  Future<void> applyNotebook(NotebookSyncRow row) {
    return _enqueue(() async {
      final existing = _notebooksBox.get(row.id);
      final created = row.createdAt;
      final stored = StoredNotebook(
        id: row.id,
        name: row.name,
        inkColorArgb: row.inkColorArgb,
        createdAtUs: created.microsecondsSinceEpoch,
        updatedAtUs: row.updatedAt.microsecondsSinceEpoch,
        deletedAtUs: row.deletedAt?.microsecondsSinceEpoch,
        syncState: 1,
        ownerId: row.ownerId ?? existing?.ownerId ?? currentUserId,
        clockFlags: clockFlagsFor(
          created: created,
          updated: row.updatedAt,
          deleted: row.deletedAt,
        ),
        version: row.version,
      );
      await _notebooksBox.put(row.id, stored);
      await _notebooksBox.flush();
      if (row.isDeleted) await _stampTombstone(row.id);
      _load();
      _emit();
    });
  }

  @override
  Future<void> applyPage(PageSyncRow row) {
    return _enqueue(() async {
      final existing = _pagesBox.get(row.id);
      final stored = StoredPage(
        id: row.id,
        notebookId: row.notebookId,
        pageIndex: row.pageIndex,
        createdAtUs: row.createdAt.microsecondsSinceEpoch,
        capturedAtUs: row.capturedAt.microsecondsSinceEpoch,
        paperLeft: row.paperLeft,
        paperTop: row.paperTop,
        paperWidth: row.paperWidth,
        paperHeight: row.paperHeight,
        recognizedText: existing?.recognizedText ?? row.recognizedText,
        markers: existing?.markers ?? row.markers,
        syncState: 1,
        deletedAtUs: row.deletedAt?.microsecondsSinceEpoch,
        ownerId: row.ownerId ?? existing?.ownerId ?? currentUserId,
        clockFlags: clockFlagsFor(
          created: row.createdAt,
          updated: row.updatedAt,
          captured: row.capturedAt,
          deleted: row.deletedAt,
        ),
        version: row.version,
        updatedAtUs: row.updatedAt.microsecondsSinceEpoch,
      );
      await _pagesBox.put(row.id, stored);
      await _pagesBox.flush();
      if (row.isDeleted) await _stampTombstone(row.id);
      _load();
      _emit();
    });
  }

  @override
  Future<void> applyStroke(StrokeSyncRow row) {
    return _enqueue(() async {
      final existing = _strokesBox.get(row.id);
      final stored = StoredStroke(
        id: row.id,
        pageId: row.pageId,
        colorArgb: row.colorArgb,
        width: row.width,
        createdAtUs: row.createdAt.microsecondsSinceEpoch,
        updatedAtUs: row.updatedAt.microsecondsSinceEpoch,
        version: row.version,
        deletedAtUs: row.deletedAt?.microsecondsSinceEpoch,
        syncState: 1,
        ownerId: row.ownerId ?? existing?.ownerId ?? currentUserId,
        packedPoints: row.points,
        timeOriginMs: row.timeOriginMs,
        clockFlags: clockFlagsFor(
          created: row.createdAt,
          updated: row.updatedAt,
          deleted: row.deletedAt,
        ),
      );
      await _strokesBox.put(row.id, stored);
      await _strokesBox.flush();
      if (row.isDeleted) await _stampTombstone(row.id);
      _load();
      _emit();
    });
  }

  @override
  Future<DateTime?> cursorFor(String table) async {
    final raw = _metaBox.get(_cursorKey(table));
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> setCursor(String table, DateTime cursor) {
    return _enqueue(() async {
      await _metaBox.put(_cursorKey(table), cursor.toUtc().toIso8601String());
      await _metaBox.flush();
    });
  }

  @override
  Future<void> quarantine(String table, String id) {
    return _enqueue(() async {
      final keys = _quarantineKeys();
      keys.add('$table:$id');
      await _metaBox.put(MetaKeys.syncQuarantine, keys.toList());
      await _metaBox.flush();
    });
  }

  @override
  Future<int> purgeSyncedTombstones({required DateTime syncedBefore}) {
    return _enqueue(() async {
      final stamps = _tombstoneStamps();
      var removed = 0;
      removed += await _purgeNotebooks(stamps, syncedBefore);
      removed += await _purgePages(stamps, syncedBefore);
      removed += await _purgeStrokes(stamps, syncedBefore);
      if (removed > 0) {
        await _metaBox.put(MetaKeys.tombstoneSyncedAt, [
          for (final entry in stamps.entries) '${entry.key}|${entry.value}',
        ]);
        await _metaBox.flush();
        _load();
        _emit();
      }
      return removed;
    });
  }

  bool _uploadable(
    String? ownerId,
    String userId,
    int syncState,
    String table,
    String id,
  ) {
    return ownerId == userId &&
        syncState == 0 &&
        !_quarantineKeys().contains('$table:$id');
  }

  Set<String> _quarantineKeys() {
    final raw = _metaBox.get(MetaKeys.syncQuarantine);
    if (raw is! List) return <String>{};
    return {
      for (final item in raw)
        if (item is String) item,
    };
  }

  String _cursorKey(String table) {
    return switch (table) {
      SyncTables.pages => MetaKeys.syncCursorPages,
      SyncTables.strokes => MetaKeys.syncCursorStrokes,
      _ => MetaKeys.syncCursorNotebooks,
    };
  }

  Future<void> _stampTombstone(String id) async {
    final stamps = _tombstoneStamps();
    stamps[id] = DateTime.now().toUtc().microsecondsSinceEpoch;
    await _metaBox.put(MetaKeys.tombstoneSyncedAt, [
      for (final entry in stamps.entries) '${entry.key}|${entry.value}',
    ]);
    await _metaBox.flush();
  }

  Map<String, int> _tombstoneStamps() {
    final raw = _metaBox.get(MetaKeys.tombstoneSyncedAt);
    final stamps = <String, int>{};
    if (raw is! List) return stamps;
    for (final item in raw) {
      if (item is! String) continue;
      final split = item.split('|');
      if (split.length != 2) continue;
      final micros = int.tryParse(split[1]);
      if (micros == null) continue;
      stamps[split[0]] = micros;
    }
    return stamps;
  }

  bool _tombstoneReady(
    Map<String, int> stamps,
    String id,
    int? deletedAtUs,
    DateTime cutoff,
  ) {
    if (deletedAtUs == null) return false;
    final stamped = stamps[id];
    final when = stamped == null
        ? DateTime.fromMicrosecondsSinceEpoch(deletedAtUs, isUtc: true)
        : DateTime.fromMicrosecondsSinceEpoch(stamped, isUtc: true);
    return when.isBefore(cutoff);
  }

  Future<int> _purgeNotebooks(Map<String, int> stamps, DateTime cutoff) async {
    var removed = 0;
    for (final key in [..._notebooksBox.keys]) {
      final stored = _notebooksBox.get(key);
      if (stored == null || stored.syncState != 1) continue;
      if (!_tombstoneReady(stamps, stored.id, stored.deletedAtUs, cutoff)) {
        continue;
      }
      await _notebooksBox.delete(key);
      stamps.remove(stored.id);
      removed += 1;
    }
    return removed;
  }

  Future<int> _purgePages(Map<String, int> stamps, DateTime cutoff) async {
    var removed = 0;
    for (final key in [..._pagesBox.keys]) {
      final stored = _pagesBox.get(key);
      if (stored == null || stored.syncState != 1) continue;
      if (!_tombstoneReady(stamps, stored.id, stored.deletedAtUs, cutoff)) {
        continue;
      }
      await _pagesBox.delete(key);
      stamps.remove(stored.id);
      removed += 1;
    }
    return removed;
  }

  Future<int> _purgeStrokes(Map<String, int> stamps, DateTime cutoff) async {
    var removed = 0;
    for (final key in [..._strokesBox.keys]) {
      final stored = _strokesBox.get(key);
      if (stored == null || stored.syncState != 1) continue;
      if (!_tombstoneReady(stamps, stored.id, stored.deletedAtUs, cutoff)) {
        continue;
      }
      await _strokesBox.delete(key);
      stamps.remove(stored.id);
      removed += 1;
    }
    return removed;
  }

  String? _pageIdOfCachedStroke(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        for (final stroke in page.strokes) {
          if (stroke.id == id) return page.id;
        }
      }
    }
    return _strokesBox.get(id)?.pageId;
  }

  NotebookSyncRow _notebookSyncRow(StoredNotebook stored) {
    return NotebookSyncRow(
      id: stored.id,
      name: stored.name,
      inkColorArgb: stored.inkColorArgb,
      version: stored.version < 1 ? 1 : stored.version,
      createdAt: clockTime(
        stored.createdAtUs,
        stored.clockFlags,
        clockCreatedUtc,
      ),
      updatedAt: clockTime(
        stored.updatedAtUs,
        stored.clockFlags,
        clockUpdatedUtc,
      ),
      deletedAt: stored.deletedAtUs == null
          ? null
          : clockTime(stored.deletedAtUs!, stored.clockFlags, clockDeletedUtc),
      syncState: stored.syncState == 1 ? SyncState.synced : SyncState.pending,
      ownerId: stored.ownerId,
    );
  }

  PageSyncRow _pageSyncRow(StoredPage stored) {
    final updatedUs = stored.updatedAtUs == 0
        ? stored.capturedAtUs
        : stored.updatedAtUs;
    return PageSyncRow(
      id: stored.id,
      notebookId: stored.notebookId,
      pageIndex: stored.pageIndex,
      paperLeft: stored.paperLeft,
      paperTop: stored.paperTop,
      paperWidth: stored.paperWidth,
      paperHeight: stored.paperHeight,
      recognizedText: stored.recognizedText,
      markers: stored.markers,
      version: stored.version < 1 ? 1 : stored.version,
      createdAt: clockTime(
        stored.createdAtUs,
        stored.clockFlags,
        clockCreatedUtc,
      ),
      capturedAt: clockTime(
        stored.capturedAtUs,
        stored.clockFlags,
        clockCapturedUtc,
      ),
      updatedAt: clockTime(updatedUs, stored.clockFlags, clockUpdatedUtc),
      deletedAt: stored.deletedAtUs == null
          ? null
          : clockTime(stored.deletedAtUs!, stored.clockFlags, clockDeletedUtc),
      syncState: stored.syncState == 1 ? SyncState.synced : SyncState.pending,
      ownerId: stored.ownerId,
    );
  }

  StrokeSyncRow _strokeSyncRow(StoredStroke stored) {
    final domain = stored.toDomain();
    final packed = packPoints(domain.points);
    return StrokeSyncRow(
      id: stored.id,
      pageId: stored.pageId,
      colorArgb: stored.colorArgb,
      width: stored.width,
      version: stored.version < 1 ? 1 : stored.version,
      createdAt: domain.createdAt,
      updatedAt: domain.updatedAt,
      deletedAt: domain.deletedAt,
      syncState: domain.syncState,
      ownerId: stored.ownerId,
      points: stored.packedPoints ?? packed.bytes,
      timeOriginMs: stored.timeOriginMs,
    );
  }
}

List<Stroke> _replacedStrokes(List<Stroke> strokes, Stroke stroke) {
  final exists = strokes.any((item) => item.id == stroke.id);
  return [
    for (final item in strokes)
      if (item.id == stroke.id) stroke else item,
    if (!exists) stroke,
  ];
}
