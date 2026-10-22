import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/link_status.dart';
import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../ble/simulated_pen_transport.dart';
import '../capture/capture_machine.dart';
import '../capture/markers.dart';
import '../data/sample_notebooks.dart';
import '../models/ink_models.dart';
import '../models/pen_link.dart';
import '../protocol/codec.dart';
import '../storage/checkpoint_scheduler.dart';
import '../storage/notebook_store.dart';
import '../theme/app_colors.dart';
import 'debug_ink_stats.dart';
import 'notebook_store_provider.dart';
import 'pen_transport_provider.dart';
import 'signal.dart';

final appControllerProvider = NotifierProvider<AppController, AppModel>(
  AppController.new,
);

class AppModel {
  const AppModel({
    required this.notebooks,
    required this.link,
    required this.nearbyPens,
    required this.liveNotebookId,
    required this.livePageId,
    required this.hover,
    required this.history,
  });

  final List<Notebook> notebooks;
  final PenLink link;
  final List<String> nearbyPens;
  final String? liveNotebookId;
  final String? livePageId;
  final StrokePoint? hover;
  final Map<String, PageHistory> history;

  static const _unset = Object();

  factory AppModel.sample() {
    return AppModel(
      notebooks: sampleNotebooks(),
      link: PenLink.paired(),
      nearbyPens: const ['PaperSync Pen'],
      liveNotebookId: null,
      livePageId: null,
      hover: null,
      history: const {},
    );
  }

  factory AppModel.empty() {
    return AppModel(
      notebooks: const [],
      link: PenLink.unpaired(permissionGranted: false),
      nearbyPens: const ['PaperSync Pen'],
      liveNotebookId: null,
      livePageId: null,
      hover: null,
      history: const {},
    );
  }

  Notebook? notebook(String id) {
    for (final item in notebooks) {
      if (item.id == id) return item;
    }
    return null;
  }

  NotebookPage? page(String id) {
    for (final notebook in notebooks) {
      for (final page in notebook.pages) {
        if (page.id == id) return page;
      }
    }
    return null;
  }

  PageHistory historyFor(String pageId) => history[pageId] ?? PageHistory.empty;

  AppModel copyWith({
    List<Notebook>? notebooks,
    PenLink? link,
    List<String>? nearbyPens,
    String? liveNotebookId,
    String? livePageId,
    Object? hover = _unset,
    Map<String, PageHistory>? history,
    bool clearLive = false,
  }) {
    return AppModel(
      notebooks: notebooks ?? this.notebooks,
      link: link ?? this.link,
      nearbyPens: nearbyPens ?? this.nearbyPens,
      liveNotebookId: clearLive
          ? null
          : (liveNotebookId ?? this.liveNotebookId),
      livePageId: clearLive ? null : (livePageId ?? this.livePageId),
      hover: hover == _unset ? this.hover : hover as StrokePoint?,
      history: history ?? this.history,
    );
  }
}

class AppController extends Notifier<AppModel> {
  AppController([this._initial]);

  final AppModel? _initial;
  late PenTransport _transport;
  late BluetoothPermissions _permissions;
  late DateTime Function() _clock;
  CaptureMachine _machine = CaptureMachine();
  StreamSubscription<List<FoundPen>>? _scanSub;
  final Map<String, String> _ids = {};
  final ValueNotifier<DebugInkStats> debugStats = ValueNotifier<DebugInkStats>(
    DebugInkStats.empty,
  );

  bool _active = true;
  int _epoch = 0;
  bool _capturing = false;
  bool _strokeOpen = false;
  bool _replaying = false;
  int _replayStrokes = 0;
  int _seqGaps = 0;
  int? _mtu;
  int? _rssi;
  LinkStatus? _linkStatus;
  DateTime? _rateStart;
  DateTime? _lastArrival;
  int _windowSamples = 0;
  int _windowNotes = 0;
  bool _historyArmed = false;
  final Map<String, String> _dirtyMoves = {};
  final CheckpointScheduler _checkpoints = CheckpointScheduler();
  late NotebookStore _store;
  bool _ownsStore = false;

  @override
  AppModel build() {
    final epoch = ++_epoch;
    _active = true;
    final transport = ref.watch(penTransportProvider);
    _transport = transport;
    _permissions = ref.watch(bluetoothPermissionsProvider);
    _clock = ref.watch(captureClockProvider);
    _machine = CaptureMachine();
    final notes = transport.notifications.listen((bytes) {
      if (epoch != _epoch) return;
      _onBytes(bytes);
    });
    final status = transport.status.listen((next) {
      if (epoch != _epoch) return;
      _onStatus(next);
    });
    final battery = transport.battery.listen((level) {
      if (epoch != _epoch) return;
      _onBattery(level);
    });
    StreamSubscription<List<Notebook>>? notebooksSub;
    ref.onDispose(() {
      _active = false;
      _epoch += 1;
      _checkpoints.stop();
      unawaited(notes.cancel());
      unawaited(status.cancel());
      unawaited(battery.cancel());
      unawaited(notebooksSub?.cancel());
      unawaited(_scanSub?.cancel());
      unawaited(transport.dispose());
      if (_ownsStore) unawaited(_store.close());
      debugStats.dispose();
    });
    final AppModel base;
    final initial = _initial;
    if (initial != null) {
      _store = MemoryNotebookStore(notebooks: initial.notebooks);
      _ownsStore = true;
      base = initial;
    } else {
      _store = ref.watch(notebookStoreProvider);
      _ownsStore = false;
      base = kDebugMode ? AppModel.sample() : AppModel.empty();
    }
    if (base.link.permissionGranted && !base.link.bonded) {
      _listenScan();
    }
    // Saved notebooks live in the store. Pulls and account switches update
    // that store without going through this controller, so the library has
    // to follow it. An open stroke and a drag still exist only here.
    notebooksSub = _store.watchNotebooks().listen((notebooks) {
      if (epoch != _epoch || !_active) return;
      _projectNotebooks(notebooks);
    }, onError: (Object _) {});
    return base.copyWith(notebooks: _store.current);
  }

  void _projectNotebooks(List<Notebook> incoming) {
    state = state.copyWith(notebooks: _overlaySessionEdits(incoming));
  }

  /// Keeps ink that has not been written yet on top of a store snapshot.
  List<Notebook> _overlaySessionEdits(List<Notebook> incoming) {
    final open = _openStrokeSnapshot();
    final moved = _dirtyStrokeSnapshots();
    if (open == null && moved.isEmpty) return incoming;
    final livePageId = open?.pageId;
    var pageKept = livePageId == null;
    final notebooks = <Notebook>[];
    for (final notebook in incoming) {
      final pages = <NotebookPage>[];
      var changed = false;
      for (final page in notebook.pages) {
        if (page.id == livePageId) pageKept = true;
        final strokes = _overlayStrokes(
          page,
          open: page.id == livePageId ? open?.stroke : null,
          moved: moved,
        );
        if (identical(strokes, page.strokes)) {
          pages.add(page);
        } else {
          changed = true;
          pages.add(page.copyWith(strokes: strokes));
        }
      }
      notebooks.add(
        changed
            ? notebook.copyWith(pages: pages, updatedAt: notebook.updatedAt)
            : notebook,
      );
    }
    if (pageKept || open == null) return notebooks;
    final localPage = state.page(open.pageId);
    if (localPage == null) return notebooks;
    return [
      for (final notebook in notebooks)
        if (notebook.id != localPage.notebookId)
          notebook
        else
          notebook.copyWith(
            pages: [...notebook.pages, localPage],
            updatedAt: notebook.updatedAt,
          ),
    ];
  }

  _OpenStroke? _openStrokeSnapshot() {
    if (!_strokeOpen) return null;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return null;
    return _OpenStroke(page.id, page.strokes.last);
  }

  Map<String, Stroke> _dirtyStrokeSnapshots() {
    if (_dirtyMoves.isEmpty) return const {};
    final moved = <String, Stroke>{};
    for (final entry in _dirtyMoves.entries) {
      final page = state.page(entry.value);
      if (page == null) continue;
      for (final stroke in page.strokes) {
        if (stroke.id == entry.key) moved[stroke.id] = stroke;
      }
    }
    return moved;
  }

  List<Stroke> _overlayStrokes(
    NotebookPage page, {
    required Stroke? open,
    required Map<String, Stroke> moved,
  }) {
    if (open == null && moved.isEmpty) return page.strokes;
    final next = <Stroke>[];
    var changed = false;
    for (final stroke in page.strokes) {
      if (open != null && stroke.id == open.id) {
        changed = true;
        continue;
      }
      final replacement = moved[stroke.id];
      if (replacement == null) {
        next.add(stroke);
      } else {
        next.add(replacement);
        changed = true;
      }
    }
    if (open != null) {
      next.add(open);
      changed = true;
    }
    return changed ? next : page.strokes;
  }

  /// Copies the open stroke into the checkpoint box and flushes it.
  ///
  /// Undo history stays in memory. A kill during a stroke keeps the last
  /// checkpoint, not the undo stack.
  Future<void> flushOpenStroke() async {
    if (!_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    await _store.writeCheckpoint(
      OpenCheckpoint(pageId: page.id, stroke: page.strokes.last),
      flush: true,
    );
    await _store.flush();
  }

  String createNotebook(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNotebookNameLength) return '';
    final now = DateTime.now();
    final notebook = Notebook(
      id: newId(),
      name: trimmed,
      pages: const [],
      inkColorArgb: AppColors.storedInk.toARGB32(),
      createdAt: now,
    );
    state = state.copyWith(notebooks: [notebook, ...state.notebooks]);
    _persist(_store.createNotebook(notebook));
    return notebook.id;
  }

  void renameNotebook(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNotebookNameLength) return;
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          if (notebook.id == id)
            notebook.copyWith(name: trimmed, syncState: SyncState.pending)
          else
            notebook,
      ],
    );
    _persist(_store.renameNotebook(id, trimmed));
  }

  String addPage(String notebookId) {
    final notebook = state.notebook(notebookId);
    if (notebook == null) return '';
    final nextIndex = notebook.pages.fold<int>(
      0,
      (max, page) => page.pageIndex > max ? page.pageIndex : max,
    );
    final now = DateTime.now();
    final page = NotebookPage(
      id: newId(),
      notebookId: notebook.id,
      pageIndex: nextIndex + 1,
      strokes: const [],
      createdAt: now,
      capturedAt: now,
      recognizedText: '',
    );
    _replaceNotebook(
      notebook.copyWith(
        pages: [...notebook.pages, page],
        syncState: SyncState.pending,
      ),
    );
    _persist(_store.addPage(page));
    return page.id;
  }

  void deletePage(String pageId) {
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          notebook.copyWith(
            pages: [
              for (final page in notebook.pages)
                if (page.id != pageId) page,
            ],
          ),
      ],
    );
    _persist(_store.softDeletePage(pageId));
  }

  void setInkColor(String notebookId, Color color) {
    final notebook = state.notebook(notebookId);
    if (notebook == null) return;
    _replaceNotebook(
      notebook.copyWith(
        inkColorArgb: color.toARGB32(),
        syncState: SyncState.pending,
      ),
    );
    _persist(_store.setInkColor(notebookId, color.toARGB32()));
  }

  void armHistory(String pageId) {
    if (_historyArmed) return;
    _pushUndo(pageId);
    _historyArmed = true;
  }

  void disarmHistory() {
    _historyArmed = false;
    _commitMoves();
  }

  void undo(String pageId) {
    final history = state.historyFor(pageId);
    final page = state.page(pageId);
    if (page == null || !history.canUndo) return;
    final previous = history.undo.last;
    final undo = history.undo.sublist(0, history.undo.length - 1);
    final redo = [
      ...history.redo,
      page.strokes.map((stroke) => stroke.copy()).toList(),
    ];
    _writePage(
      pageId,
      page.copyWith(strokes: previous),
      PageHistory(undo: undo, redo: redo),
    );
  }

  void redo(String pageId) {
    final history = state.historyFor(pageId);
    final page = state.page(pageId);
    if (page == null || !history.canRedo) return;
    final next = history.redo.last;
    final redo = history.redo.sublist(0, history.redo.length - 1);
    final undo = [
      ...history.undo,
      page.strokes.map((stroke) => stroke.copy()).toList(),
    ];
    _writePage(
      pageId,
      page.copyWith(strokes: next),
      PageHistory(undo: undo, redo: redo),
    );
  }

  void recolorStroke(String pageId, String strokeId, Color color) {
    final page = state.page(pageId);
    if (page == null) return;
    _pushUndo(pageId);
    final current = state.page(pageId)!;
    _replacePage(
      current.copyWith(
        strokes: [
          for (final stroke in current.strokes)
            if (stroke.id == strokeId)
              stroke.edited(colorArgb: color.toARGB32())
            else
              stroke,
        ],
      ),
    );
    final saved = state.page(pageId)?.strokes.where((stroke) {
      return stroke.id == strokeId;
    });
    if (saved != null && saved.isNotEmpty) {
      _persist(_store.upsertStroke(pageId, saved.first));
    }
  }

  void eraseStroke(String pageId, String strokeId) {
    final page = state.page(pageId);
    if (page == null) return;
    if (!page.strokes.any(
      (stroke) => stroke.id == strokeId && stroke.deletedAt == null,
    )) {
      return;
    }
    _pushUndo(pageId);
    final current = state.page(pageId)!;
    _replacePage(
      current.copyWith(
        strokes: [
          for (final stroke in current.strokes)
            if (stroke.id == strokeId) stroke.erased() else stroke,
        ],
      ),
    );
    final saved = state.page(pageId)?.strokes.where((stroke) {
      return stroke.id == strokeId;
    });
    if (saved != null && saved.isNotEmpty) {
      _persist(_store.upsertStroke(pageId, saved.first));
    }
  }

  void moveStroke(String pageId, String strokeId, Offset deltaMm) {
    final page = state.page(pageId);
    if (page == null) return;
    _replacePage(
      page.copyWith(
        strokes: [
          for (final stroke in page.strokes)
            if (stroke.id == strokeId)
              stroke.copyWith(
                points: [
                  for (final point in stroke.points)
                    point.shift(deltaMm.dx, deltaMm.dy),
                ],
              )
            else
              stroke,
        ],
      ),
    );
    _dirtyMoves[strokeId] = pageId;
  }

  void grantPermission() {
    unawaited(_grant());
  }

  void connectPen(String name) {
    if (!_active) return;
    state = state.copyWith(
      link: state.link.copyWith(
        bonded: true,
        penName: name,
        permissionGranted: true,
        state: LinkState.reconnecting,
      ),
    );
    unawaited(_transport.connect(_ids[name] ?? name));
  }

  void disconnectPen() {
    unawaited(_transport.disconnect());
  }

  void forgetPen() {
    unawaited(_transport.forget());
    stopLive();
    if (!_active) return;
    state = state.copyWith(
      link: PenLink.unpaired(permissionGranted: state.link.permissionGranted),
      clearLive: true,
    );
  }

  void startLive(String notebookId) {
    stopLive();
    if (!_active) return;
    if (state.notebook(notebookId) == null) return;
    if (state.notebook(notebookId)!.pages.isEmpty) {
      addPage(notebookId);
    }
    final notebook = state.notebook(notebookId)!;
    final page = notebook.pages.reduce(
      (a, b) => a.pageIndex > b.pageIndex ? a : b,
    );
    _machine = CaptureMachine(strokesOnPage: page.strokes.length);
    _strokeOpen = false;
    _capturing = true;
    state = state.copyWith(
      liveNotebookId: notebookId,
      livePageId: page.id,
      hover: null,
    );
    final transport = _transport;
    if (transport is SimulatedPenTransport && state.link.connected) {
      transport.play();
    }
  }

  void stopLive() {
    _capturing = false;
    final transport = _transport;
    if (transport is SimulatedPenTransport) transport.stop();
    if (!_active) return;
    _checkpoints.stop();
    for (final event in _machine.disconnect()) {
      _apply(event);
    }
    if (state.hover != null) {
      state = state.copyWith(hover: null);
    }
  }

  Future<void> _grant() async {
    PermissionOutcome outcome;
    try {
      outcome = await _permissions.grant();
    } on Object {
      outcome = PermissionOutcome.denied;
    }
    if (!_active) return;
    switch (outcome) {
      case PermissionOutcome.granted:
        state = state.copyWith(
          link: state.link.copyWith(permissionGranted: true),
        );
        _listenScan();
      case PermissionOutcome.denied:
        _onStatus(const Unavailable('Bluetooth permission denied'));
      case PermissionOutcome.permanentlyDenied:
        _onStatus(const Unavailable('Bluetooth permission permanently denied'));
    }
  }

  void _listenScan() {
    _scanSub ??= _transport.scan().listen((pens) {
      if (!_active) return;
      _ids
        ..clear()
        ..addEntries([for (final pen in pens) MapEntry(pen.name, pen.id)]);
      state = state.copyWith(nearbyPens: [for (final pen in pens) pen.name]);
    });
  }

  void _onBytes(Uint8List bytes) {
    if (!_capturing || !_active) return;
    final arrival = _clock();
    final result = decode(bytes);
    final sampleCount = switch (result) {
      Decoded(:final notification) => notification.samples.length,
      Rejected() => 0,
    };
    _noteRate(sampleCount, arrival);
    final events = _machine.ingest(result, arrival: arrival);
    for (final event in events) {
      _apply(event);
    }
    if (!_active) return;
    state = state.copyWith(link: state.link.copyWith(lastPacket: arrival));
  }

  void _onStatus(LinkStatus status) {
    if (!_active) return;
    _linkStatus = status;
    final dropped = switch (status) {
      Disconnected() || Unavailable() => true,
      Connecting() || Connected() || Reconnecting() => false,
    };
    if (dropped && _capturing) {
      for (final event in _machine.disconnect()) {
        _apply(event);
      }
    }
    _paintLink(saved: false);
    _publishDebug();
  }

  void _onBattery(int level) {
    if (!_active) return;
    final clamped = level < 0 ? 0 : (level > 100 ? 100 : level);
    state = state.copyWith(link: state.link.copyWith(batteryPercent: clamped));
  }

  void _apply(CaptureEvent event) {
    if (!_active) return;
    switch (event) {
      case StrokeOpened(:final point):
        _openStroke(point);
        if (_replaying) {
          _replayStrokes += 1;
          _paintLink(saved: false);
        }
      case PointAdded(:final point):
        _addPoint(point);
      case StrokeClosed():
        final pageId = state.livePageId;
        final page = pageId == null ? null : state.page(pageId);
        _strokeOpen = false;
        _checkpoints.stop();
        if (page != null && page.strokes.isNotEmpty) {
          _persist(_store.saveClosedStroke(page.id, page.strokes.last));
        }
      case HoverMoved(:final point):
        state = state.copyWith(hover: point);
      case HoverLost():
        if (state.hover != null) state = state.copyWith(hover: null);
      case PageTurned():
        _turnLivePage();
      case SamplesLost(:final count):
        _seqGaps += count;
        _markLoss(count);
        _publishDebug();
      case ReplayStarted():
        _replaying = true;
        _replayStrokes = 0;
        _paintLink(saved: false);
        _publishDebug();
      case ReplayEnded():
        _replaying = false;
        _replayStrokes = 0;
        _paintLink(saved: true);
        _publishDebug();
      case ProtocolError():
        break;
    }
  }

  void _openStroke(StrokePoint point) {
    final pageId = state.livePageId;
    final notebookId = state.liveNotebookId;
    final page = pageId == null ? null : state.page(pageId);
    final notebook = notebookId == null ? null : state.notebook(notebookId);
    if (page == null || notebook == null) return;
    final stroke = Stroke(
      id: newId(),
      points: [point],
      colorArgb: notebook.inkColorArgb,
      createdAt: _when(point),
    );
    _replacePage(page.copyWith(strokes: [...page.strokes, stroke]));
    _strokeOpen = true;
    _checkpoints.start(_checkpointTick);
    if (state.hover != null) state = state.copyWith(hover: null);
  }

  void _addPoint(StrokePoint point) {
    if (!_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    final last = page.strokes.last;
    final strokes = [
      ...page.strokes.sublist(0, page.strokes.length - 1),
      last.copyWith(points: [...last.points, point]),
    ];
    _replacePage(page.copyWith(strokes: strokes));
  }

  void _turnLivePage() {
    final notebookId = state.liveNotebookId;
    if (notebookId == null) return;
    final id = addPage(notebookId);
    if (id.isEmpty) return;
    _strokeOpen = false;
    state = state.copyWith(livePageId: id, hover: null);
  }

  void _markLoss(int count) {
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null) return;
    final saved = page.copyWith(
      markers: [...page.markers, samplesLostMarker(count)],
      syncState: SyncState.pending,
    );
    _replacePage(saved);
    _persist(_store.savePage(saved));
  }

  void _paintLink({required bool saved}) {
    final status = _linkStatus;
    if (status == null || !_active) return;
    final previous = state.link;
    switch (status) {
      case Unavailable(:final reason):
        final denied = reason.toLowerCase().contains('permission');
        state = state.copyWith(
          link: previous.copyWith(
            state: LinkState.disconnected,
            signal: 'None',
            queuedStrokes: 0,
            permissionGranted: denied ? false : previous.permissionGranted,
          ),
        );
      case Disconnected():
        state = state.copyWith(
          link: previous.copyWith(
            state: LinkState.disconnected,
            signal: 'None',
            queuedStrokes: 0,
            lastSaved: previous.lastSaved ?? _clock(),
          ),
        );
      case Connecting():
      case Reconnecting():
        state = state.copyWith(
          link: previous.copyWith(
            state: LinkState.reconnecting,
            queuedStrokes: _replaying ? _replayStrokes : previous.queuedStrokes,
          ),
        );
      case Connected(:final mtu, :final rssi):
        _mtu = mtu;
        _rssi = rssi;
        state = state.copyWith(
          link: previous.copyWith(
            state: _replaying ? LinkState.reconnecting : LinkState.saving,
            bonded: true,
            permissionGranted: true,
            signal: signalForRssi(rssi),
            penName: previous.penName ?? 'PaperSync Pen',
            queuedStrokes: _replaying ? _replayStrokes : 0,
            lastSaved: saved ? _clock() : previous.lastSaved,
          ),
        );
    }
  }

  void _noteRate(int samples, DateTime now) {
    _lastArrival = now;
    _rateStart ??= now;
    final elapsed = now.difference(_rateStart!).inMilliseconds;
    if (elapsed >= 1000) {
      _publishDebug();
      _rateStart = now;
      _windowSamples = samples;
      _windowNotes = 1;
    } else {
      _windowSamples += samples;
      _windowNotes += 1;
    }
    _publishDebug();
  }

  void _publishDebug() {
    if (!kDebugMode || !_active) return;
    final start = _rateStart;
    final end = _lastArrival;
    final elapsed = start == null || end == null
        ? 0
        : end.difference(start).inMilliseconds;
    final seconds = elapsed <= 0 ? 1.0 : elapsed / 1000.0;
    debugStats.value = DebugInkStats(
      samplesPerSecond: _windowSamples / seconds,
      notificationsPerSecond: _windowNotes / seconds,
      mtu: _mtu,
      seqGaps: _seqGaps,
      rssi: _rssi,
      replay: _replaying,
    );
  }

  DateTime _when(StrokePoint point) {
    if (point.tMs <= 0) return _clock();
    return DateTime.fromMillisecondsSinceEpoch(point.tMs);
  }

  void _pushUndo(String pageId) {
    final page = state.page(pageId);
    if (page == null) return;
    final history = state.historyFor(pageId);
    final undo = [
      ...history.undo,
      page.strokes.map((stroke) => stroke.copy()).toList(),
    ];
    if (undo.length > 50) undo.removeAt(0);
    _setHistory(pageId, PageHistory(undo: undo, redo: const []));
  }

  void _setHistory(String pageId, PageHistory history) {
    state = state.copyWith(history: {...state.history, pageId: history});
  }

  void _writePage(String pageId, NotebookPage page, PageHistory history) {
    _replacePage(page);
    _setHistory(pageId, history);
    for (final stroke in page.strokes) {
      _persist(_store.upsertStroke(pageId, stroke));
    }
    _persist(_store.savePage(page));
  }

  void _commitMoves() {
    if (_dirtyMoves.isEmpty) return;
    final pending = Map<String, String>.of(_dirtyMoves);
    _dirtyMoves.clear();
    for (final entry in pending.entries) {
      final pageId = entry.value;
      final strokeId = entry.key;
      final page = state.page(pageId);
      if (page == null) continue;
      final index = page.strokes.indexWhere((stroke) => stroke.id == strokeId);
      if (index < 0) continue;
      final current = page.strokes[index];
      final saved = current.edited(points: current.points);
      final strokes = [...page.strokes];
      strokes[index] = saved;
      _replacePage(page.copyWith(strokes: strokes));
      _persist(_store.upsertStroke(pageId, saved));
    }
  }

  void _checkpointTick() {
    if (!_active || !_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    _persist(
      _store.writeCheckpoint(
        OpenCheckpoint(pageId: page.id, stroke: page.strokes.last),
      ),
    );
  }

  void _persist(Future<void> write) {
    unawaited(write.catchError((Object _) {}));
  }

  void _replacePage(NotebookPage page) {
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          notebook.copyWith(
            pages: [
              for (final current in notebook.pages)
                if (current.id == page.id) page else current,
            ],
          ),
      ],
    );
  }

  void _replaceNotebook(Notebook notebook) {
    state = state.copyWith(
      notebooks: [
        for (final current in state.notebooks)
          if (current.id == notebook.id) notebook else current,
      ],
    );
  }
}

class _OpenStroke {
  const _OpenStroke(this.pageId, this.stroke);

  final String pageId;
  final Stroke stroke;
}
