import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:papersync/data/sample_notebooks.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/notebook_store_provider.dart';
import 'package:papersync/storage/adapters.dart';
import 'package:papersync/storage/key_store.dart';
import 'package:papersync/storage/notebook_store.dart';
import 'package:papersync/storage/records.dart';
import 'package:papersync/storage/schema.dart';
import 'package:papersync/storage/session.dart';

void main() {
  test('restart returns the same notebooks', () async {
    final harness = await _Harness.open();
    final notebook = _notebook();
    await harness.store.createNotebook(notebook);
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    final loaded = again.store.current.single;
    expect(loaded.name, notebook.name);
    expect(loaded.syncState, SyncState.pending);
    expect(loaded.pages.single.recognizedText, 'hello');
    expect(loaded.pages.single.markers, ['3 samples lost']);
    expect(loaded.pages.single.strokes, notebook.pages.single.strokes);
    await again.close();
    harness.delete();
  });

  test('a leftover checkpoint is recovered once', () async {
    final harness = await _Harness.open();
    final page = _page(strokes: const []);
    await harness.store.createNotebook(_notebook(page: page));
    final recovered = _stroke(id: 'stroke-recovered', tMs: 1000);
    await harness.store.writeCheckpoint(
      OpenCheckpoint(pageId: page.id, stroke: recovered),
      flush: true,
    );
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    final strokes = again.store.current.single.pages.single.strokes;
    expect(strokes, hasLength(1));
    expect(strokes.single.id, recovered.id);
    expect(strokes.single.points, recovered.points);
    await again.close();

    final third = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    expect(third.store.current.single.pages.single.strokes, hasLength(1));
    await third.close();
    harness.delete();
  });

  test('a checkpoint does not replace a stroke already stored', () async {
    final harness = await _Harness.open();
    final stored = _stroke(id: 'stroke-kept', tMs: 1000);
    final page = _page(strokes: [stored]);
    await harness.store.createNotebook(_notebook(page: page));
    final newer = _stroke(id: stored.id, tMs: 1000, extra: true);
    await harness.store.writeCheckpoint(
      OpenCheckpoint(pageId: page.id, stroke: newer),
      flush: true,
    );
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    final strokes = again.store.current.single.pages.single.strokes;
    expect(strokes, hasLength(1));
    expect(strokes.single.points.length, stored.points.length);
    await again.close();
    harness.delete();
  });

  test('a v1 box upgrades to the current schema', () async {
    final harness = await _Harness.open();
    await harness.close();
    await _writeV1(harness);

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    final stroke = again.store.current.single.pages.single.strokes.single;
    expect(stroke.points.single.xMm, 12.5);
    expect(stroke.points.single.yMm, 40);
    expect(stroke.points.single.tMs, 1000);
    await again.close();

    registerStorageAdapters();
    final meta = await Hive.openBox<Object>(
      BoxNames.meta,
      path: harness.directory.path,
      encryptionCipher: HiveAesCipher((await harness.keys.readKey())!),
    );
    expect(meta.get(MetaKeys.schemaVersion), currentSchemaVersion);
    final installId = meta.get(MetaKeys.installId);
    expect(installId, isA<String>());
    expect((installId! as String).isNotEmpty, isTrue);
    await meta.close();
    harness.delete();
  });

  test('garbage box bytes are quarantined without throwing', () async {
    final harness = await _Harness.open();
    await harness.store.createNotebook(_notebook());
    await harness.close();
    File('${harness.directory.path}/notebooks.hive')
        .writeAsBytesSync(List<int>.filled(64, 7));

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    expect(again.notice, storageQuarantineNotice);
    expect(again.store.current, isEmpty);
    final names = harness.directory.listSync().map((entity) => entity.path);
    expect(names.any((path) => path.contains('notebooks.corrupt-')), isTrue);
    await again.store.createNotebook(_notebook(name: 'After quarantine'));
    expect(again.store.current.single.name, 'After quarantine');
    await again.close();
    harness.delete();
  });

  test('encrypted box bytes do not contain the notebook name', () async {
    const name = 'ZephyrNotebookName';
    final harness = await _Harness.open();
    await harness.store.createNotebook(_notebook(name: name));
    await harness.close();
    final bytes = File('${harness.directory.path}/notebooks.hive')
        .readAsBytesSync();
    expect(_containsAscii(bytes, name), isFalse);
    harness.delete();
  });

  test('a missing key quarantines existing boxes', () async {
    final harness = await _Harness.open();
    await harness.store.createNotebook(_notebook());
    await harness.close();
    await harness.keys.deleteKey();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    expect(again.notice, storageQuarantineNotice);
    expect(again.store.current, isEmpty);
    expect(
      harness.directory.listSync().any(
        (entity) => entity.path.contains('.corrupt-'),
      ),
      isTrue,
    );
    await again.close();
    harness.delete();
  });

  test('sign-out keeps the signed-in account after a restart', () async {
    final harness = await _Harness.open();
    await harness.store.createNotebook(
      _notebook(name: 'Mine'),
      ownerId: 'user-a',
    );
    await harness.store.rememberHomeUser('user-a');
    await harness.store.adoptUser(null);
    expect(harness.store.current.single.name, 'Mine');
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    expect(again.store.current.single.name, 'Mine');
    await again.close();
    harness.delete();
  });

  test('another owner is hidden until that user opens the boxes', () async {
    final harness = await _Harness.open();
    await harness.store.createNotebook(
      _notebook(name: 'Private'),
      ownerId: 'other',
    );
    expect(harness.store.current, isEmpty);
    await harness.close();

    final theirs = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
      currentUserId: 'other',
    );
    expect(theirs.store.current.single.name, 'Private');
    await theirs.close();
    harness.delete();
  });

  test('a deleted page stays a tombstone and leaves the library', () async {
    final harness = await _Harness.open();
    final keep = _page(id: 'page-keep', index: 1);
    final drop = _page(id: 'page-drop', index: 2);
    await harness.store.createNotebook(
      _notebook(page: keep).copyWith(pages: [keep, drop]),
    );
    await harness.store.softDeletePage(drop.id, at: DateTime.utc(2026, 9, 26));
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    expect(
      again.store.current.single.pages.map((NotebookPage page) => page.id),
      ['page-keep'],
    );
    await again.close();
    harness.delete();
  });

  test('local edits are marked pending', () async {
    final harness = await _Harness.open();
    final stroke = _stroke().copyWith(syncState: SyncState.synced);
    final page = _page(strokes: [stroke]);
    await harness.store.createNotebook(_notebook(page: page));
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
    );
    expect(
      again.store.current.single.pages.single.strokes.single.syncState,
      SyncState.pending,
    );
    await again.close();
    harness.delete();
  });

  test('release startup with no seed is an empty library', () async {
    final harness = await _Harness.open(seed: const []);
    expect(harness.store.current, isEmpty);
    expect(harness.notice, isNull);
    await harness.close();
    harness.delete();
  });

  test('debug seed runs once', () async {
    final harness = await _Harness.open(seed: sampleNotebooks());
    expect(harness.store.current.map((Notebook notebook) => notebook.name), [
      'Lecture notes',
      'Studio',
    ]);
    await harness.close();

    final again = await _Harness.open(
      directory: harness.directory,
      keys: harness.keys,
      seed: sampleNotebooks(),
    );
    expect(again.store.current, hasLength(2));
    await again.close();
    harness.delete();
  });

  test('a move saves once with one version bump', () async {
    final now = DateTime.utc(2026, 9, 26);
    final stroke = _stroke();
    final page = _page(strokes: [stroke]);
    final notebook = _notebook(page: page);
    final store = MemoryNotebookStore(notebooks: [notebook]);
    final container = ProviderContainer(
      overrides: [notebookStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    addTearDown(store.close);
    container.read(appControllerProvider);
    final controller = container.read(appControllerProvider.notifier);
    controller.armHistory(page.id);
    controller.moveStroke(page.id, stroke.id, const Offset(1, 0));
    controller.moveStroke(page.id, stroke.id, const Offset(1, 0));
    expect(
      container
          .read(appControllerProvider)
          .page(page.id)!
          .strokes
          .single
          .version,
      1,
    );
    controller.disarmHistory();
    final saved = store.current.single.pages.single.strokes.single;
    expect(saved.version, 2);
    expect(saved.points.first.xMm, stroke.points.first.xMm + 2);
    expect(
      saved.updatedAt.isAfter(now.subtract(const Duration(days: 1))),
      isTrue,
    );
  });
}

class _Harness {
  _Harness(this.directory, this.keys, this.session);

  final Directory directory;
  final MemoryKeyStore keys;
  final StorageSession session;

  NotebookStore get store => session.store;
  String? get notice => session.notice;

  static Future<_Harness> open({
    Directory? directory,
    MemoryKeyStore? keys,
    List<Notebook>? seed,
    String? currentUserId,
  }) async {
    final dir =
        directory ?? await Directory.systemTemp.createTemp('papersync-store-');
    final storeKeys = keys ?? MemoryKeyStore();
    final session = await openPaperSyncStorage(
      keyStore: storeKeys,
      directory: dir.path,
      encrypt: true,
      seed: seed ?? const [],
      currentUserId: currentUserId,
      debounce: Duration.zero,
    );
    return _Harness(dir, storeKeys, session);
  }

  Future<void> close() => session.close();

  void delete() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

Future<void> _writeV1(_Harness harness) async {
  registerStorageAdapters();
  final cipher = HiveAesCipher((await harness.keys.readKey())!);
  final path = harness.directory.path;
  final meta = await Hive.openBox<Object>(
    BoxNames.meta,
    path: path,
    encryptionCipher: cipher,
  );
  await meta.put(MetaKeys.schemaVersion, 1);
  final notebooks = await Hive.openBox<StoredNotebook>(
    BoxNames.notebooks,
    path: path,
    encryptionCipher: cipher,
  );
  final pages = await Hive.openBox<StoredPage>(
    BoxNames.pages,
    path: path,
    encryptionCipher: cipher,
  );
  final strokes = await Hive.openBox<StoredStroke>(
    BoxNames.strokes,
    path: path,
    encryptionCipher: cipher,
  );
  const when = 1760000000000000;
  await notebooks.put(
    'nb-v1',
    const StoredNotebook(
      id: 'nb-v1',
      name: 'Legacy',
      inkColorArgb: 0xFF1C1917,
      createdAtUs: when,
      updatedAtUs: when,
      syncState: 0,
    ),
  );
  await pages.put(
    'page-v1',
    const StoredPage(
      id: 'page-v1',
      notebookId: 'nb-v1',
      pageIndex: 1,
      createdAtUs: when,
      capturedAtUs: when,
      paperLeft: 0,
      paperTop: 0,
      paperWidth: 170,
      paperHeight: 107,
      recognizedText: '',
      markers: [],
      syncState: 0,
    ),
  );
  await strokes.put(
    'stroke-v1',
    const StoredStroke(
      id: 'stroke-v1',
      pageId: 'page-v1',
      colorArgb: 0xFF1C1917,
      width: 1,
      createdAtUs: when,
      updatedAtUs: when,
      version: 1,
      syncState: 0,
      timeOriginMs: 0,
      legacyPoints: [
        StoredPoint(xMm: 12.5, yMm: 40, pressure: 100, flags: 1, tMs: 1000),
      ],
    ),
  );
  await meta.close();
  await notebooks.close();
  await pages.close();
  await strokes.close();
}

Notebook _notebook({String name = 'Field notes', NotebookPage? page}) {
  final when = DateTime.utc(2026, 9, 26);
  return Notebook(
    id: 'nb-field',
    name: name,
    inkColorArgb: 0xFF1C1917,
    createdAt: when,
    updatedAt: when,
    pages: [page ?? _page()],
  );
}

NotebookPage _page({
  String id = 'page-field',
  int index = 1,
  List<Stroke>? strokes,
}) {
  final when = DateTime.utc(2026, 9, 26);
  return NotebookPage(
    id: id,
    notebookId: 'nb-field',
    pageIndex: index,
    createdAt: when,
    capturedAt: when,
    recognizedText: 'hello',
    markers: const ['3 samples lost'],
    strokes: strokes ?? [_stroke()],
  );
}

Stroke _stroke({
  String id = 'stroke-field',
  int tMs = 1000,
  bool extra = false,
}) {
  final when = DateTime.utc(2026, 9, 26);
  return Stroke(
    id: id,
    colorArgb: 0xFF1C1917,
    width: 1.5,
    createdAt: when,
    updatedAt: when,
    points: [
      StrokePoint(
        xMm: 10.5,
        yMm: 20.25,
        pressure: 100,
        touching: true,
        tMs: tMs,
      ),
      if (extra)
        StrokePoint(
          xMm: 11,
          yMm: 21,
          pressure: 120,
          touching: true,
          tMs: tMs + 40,
        ),
    ],
  );
}

bool _containsAscii(Uint8List bytes, String text) {
  final needle = text.codeUnits;
  if (needle.isEmpty || bytes.length < needle.length) return false;
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
