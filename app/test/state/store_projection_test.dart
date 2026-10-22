import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/notebook_store_provider.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/storage/notebook_store.dart';

void main() {
  test(
    'a notebook written into the store shows up without a restart',
    () async {
      final store = MemoryNotebookStore();
      final container = _container(store);
      addTearDown(() async {
        container.dispose();
        await store.close();
      });

      container.read(appControllerProvider);
      expect(container.read(appControllerProvider).notebooks, isEmpty);

      await store.createNotebook(
        _notebook('nb-remote', 'From the other phone'),
      );
      await _flush();

      expect(
        container
            .read(appControllerProvider)
            .notebooks
            .map((item) => item.name),
        ['From the other phone'],
      );
    },
  );

  test('signing in as someone else hides the previous account', () async {
    final store = MemoryNotebookStore();
    await store.rememberHomeUser('user-a');
    await store.createNotebook(
      _notebook('nb-a', 'Alice notes'),
      ownerId: 'user-a',
    );
    final container = _container(store);
    addTearDown(() async {
      container.dispose();
      await store.close();
    });

    container.read(appControllerProvider);
    await _flush();
    expect(
      container.read(appControllerProvider).notebooks.map((item) => item.id),
      ['nb-a'],
    );

    await store.adoptUser('user-b');
    await _flush();
    expect(container.read(appControllerProvider).notebooks, isEmpty);

    await store.createNotebook(
      _notebook('nb-b', 'Bob notes'),
      ownerId: 'user-b',
    );
    await _flush();
    expect(
      container.read(appControllerProvider).notebooks.map((item) => item.name),
      ['Bob notes'],
    );
  });

  test('a store update keeps the stroke that is still being drawn', () async {
    final now = DateTime.utc(2026, 9, 27);
    final store = MemoryNotebookStore(
      notebooks: [_notebook('nb-one', 'Field')],
    );
    final transport = SimulatedPenTransport(
      clock: () => now,
      seed: 2,
      scenario: PenScenario.seqGap,
      manual: true,
    );
    final container = _container(store, transport: transport);
    addTearDown(() async {
      container.dispose();
      await store.close();
    });

    final controller = container.read(appControllerProvider.notifier);
    controller.startLive('nb-one');
    transport.step();
    final liveId = container.read(appControllerProvider).livePageId!;
    expect(
      container.read(appControllerProvider).page(liveId)!.strokes.single.points,
      hasLength(2),
    );

    await store.createNotebook(_notebook('nb-remote', 'From the other phone'));
    await _flush();

    final model = container.read(appControllerProvider);
    expect(model.notebooks.map((item) => item.id), contains('nb-remote'));
    expect(model.page(liveId)!.strokes.single.points, hasLength(2));
    transport.step();
    expect(
      container.read(appControllerProvider).page(liveId)!.strokes,
      hasLength(1),
    );
    expect(
      container
          .read(appControllerProvider)
          .page(liveId)!
          .strokes
          .single
          .points
          .length,
      greaterThan(2),
    );
  });

  test('a store update does not drop an in-progress move', () async {
    final now = DateTime.utc(2026, 9, 27);
    final stroke = Stroke(
      id: 'stroke-1',
      points: [
        StrokePoint(xMm: 10, yMm: 10, pressure: 1, touching: true, tMs: 1),
      ],
      colorArgb: 0xFF1C1917,
      createdAt: now,
    );
    final store = MemoryNotebookStore(
      notebooks: [
        _notebook(
          'nb-one',
          'Field',
          page: NotebookPage(
            id: 'page-1',
            notebookId: 'nb-one',
            pageIndex: 1,
            strokes: [stroke],
            createdAt: now,
          ),
        ),
      ],
    );
    final container = _container(store);
    addTearDown(() async {
      container.dispose();
      await store.close();
    });

    final controller = container.read(appControllerProvider.notifier);
    controller.armHistory('page-1');
    controller.moveStroke('page-1', stroke.id, const Offset(4, 0));
    await store.createNotebook(_notebook('nb-remote', 'Elsewhere'));
    await _flush();

    final saved = container.read(appControllerProvider).page('page-1')!;
    expect(saved.strokes.single.points.first.xMm, 14);
    expect(saved.strokes.single.version, 1);
  });
}

ProviderContainer _container(
  MemoryNotebookStore store, {
  SimulatedPenTransport? transport,
}) {
  return ProviderContainer(
    overrides: [
      notebookStoreProvider.overrideWithValue(store),
      if (transport != null) penTransportProvider.overrideWithValue(transport),
    ],
  );
}

Notebook _notebook(String id, String name, {NotebookPage? page}) {
  final now = DateTime.utc(2026, 9, 27);
  return Notebook(
    id: id,
    name: name,
    inkColorArgb: 0xFF1C1917,
    createdAt: now,
    pages: [
      page ??
          NotebookPage(
            id: '$id-page',
            notebookId: id,
            pageIndex: 1,
            strokes: const [],
            createdAt: now,
          ),
    ],
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
