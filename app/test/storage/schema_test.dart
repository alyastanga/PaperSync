import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/storage/schema.dart';

void main() {
  test('type ids and field indexes stay fixed', () {
    expect(TypeIds.notebook, 1);
    expect(TypeIds.page, 2);
    expect(TypeIds.stroke, 3);
    expect(TypeIds.point, 4);
    expect(TypeIds.checkpoint, 5);

    expect(NotebookFields.id, 0);
    expect(NotebookFields.name, 1);
    expect(NotebookFields.inkColorArgb, 2);
    expect(NotebookFields.createdAt, 3);
    expect(NotebookFields.updatedAt, 4);
    expect(NotebookFields.deletedAt, 5);
    expect(NotebookFields.syncState, 6);
    expect(NotebookFields.ownerId, 7);
    expect(NotebookFields.clockFlags, 8);
    expect(NotebookFields.version, 9);

    expect(PageFields.id, 0);
    expect(PageFields.notebookId, 1);
    expect(PageFields.pageIndex, 2);
    expect(PageFields.createdAt, 3);
    expect(PageFields.capturedAt, 4);
    expect(PageFields.paperLeft, 5);
    expect(PageFields.paperTop, 6);
    expect(PageFields.paperWidth, 7);
    expect(PageFields.paperHeight, 8);
    expect(PageFields.recognizedText, 9);
    expect(PageFields.markers, 10);
    expect(PageFields.syncState, 11);
    expect(PageFields.ownerId, 12);
    expect(PageFields.deletedAt, 13);
    expect(PageFields.clockFlags, 14);
    expect(PageFields.version, 15);
    expect(PageFields.updatedAt, 16);

    expect(StrokeFields.id, 0);
    expect(StrokeFields.pageId, 1);
    expect(StrokeFields.colorArgb, 2);
    expect(StrokeFields.width, 3);
    expect(StrokeFields.createdAt, 4);
    expect(StrokeFields.updatedAt, 5);
    expect(StrokeFields.version, 6);
    expect(StrokeFields.deletedAt, 7);
    expect(StrokeFields.syncState, 8);
    expect(StrokeFields.ownerId, 9);
    expect(StrokeFields.packedPoints, 10);
    expect(StrokeFields.timeOriginMs, 11);
    expect(StrokeFields.legacyPoints, 12);
    expect(StrokeFields.clockFlags, 13);

    expect(PointFields.xMm, 0);
    expect(PointFields.yMm, 1);
    expect(PointFields.pressure, 2);
    expect(PointFields.flags, 3);
    expect(PointFields.tMs, 4);

    expect(CheckpointFields.strokeId, 0);
    expect(CheckpointFields.pageId, 1);
    expect(CheckpointFields.colorArgb, 2);
    expect(CheckpointFields.width, 3);
    expect(CheckpointFields.createdAt, 4);
    expect(CheckpointFields.updatedAt, 5);
    expect(CheckpointFields.version, 6);
    expect(CheckpointFields.packedPoints, 7);
    expect(CheckpointFields.timeOriginMs, 8);
    expect(CheckpointFields.syncState, 9);
    expect(CheckpointFields.clockFlags, 10);

    expect(currentSchemaVersion, 2);
    expect(checkpointInterval, const Duration(milliseconds: 500));
  });

  test('sample notebooks are seeded only for a debug launch', () {
    expect(
      shouldSeedSamples(seedRequested: false, alreadySeeded: false),
      isFalse,
    );
    expect(
      shouldSeedSamples(seedRequested: true, alreadySeeded: false),
      isTrue,
    );
    expect(
      shouldSeedSamples(seedRequested: true, alreadySeeded: true),
      isFalse,
    );
  });
}
