/// Type ids, field indexes, and box names for the on-device boxes.
///
/// An id or index in this file is never reused or renumbered. Adapters and
/// the schema test both read these constants.
library;

/// How often an open stroke is copied into the checkpoint box.
const Duration checkpointInterval = Duration(milliseconds: 500);

/// Boxes written by the current adapters.
const int currentSchemaVersion = 2;

/// Shown when a box file is set aside instead of opened.
const String storageQuarantineNotice =
    "Some notes couldn't be opened. A copy was kept.";

/// `true` when this launch should copy the debug sample notebooks in.
bool shouldSeedSamples({
  required bool seedRequested,
  required bool alreadySeeded,
}) {
  return seedRequested && !alreadySeeded;
}

abstract final class TypeIds {
  static const notebook = 1;
  static const page = 2;
  static const stroke = 3;
  static const point = 4;
  static const checkpoint = 5;
}

abstract final class BoxNames {
  static const notebooks = 'notebooks';
  static const pages = 'pages';
  static const strokes = 'strokes';
  static const checkpoint = 'checkpoint';
  static const meta = 'meta';

  static const all = <String>[notebooks, pages, strokes, checkpoint, meta];
}

abstract final class MetaKeys {
  static const schemaVersion = 'schemaVersion';
  static const installId = 'installId';
  static const seeded = 'seeded';
  static const syncCursorNotebooks = 'syncCursorNotebooks';
  static const syncCursorPages = 'syncCursorPages';
  static const syncCursorStrokes = 'syncCursorStrokes';
  static const syncQuarantine = 'syncQuarantine';
  static const tombstoneSyncedAt = 'tombstoneSyncedAt';
  static const homeUserId = 'homeUserId';
}

abstract final class SyncTables {
  static const notebooks = 'notebooks';
  static const pages = 'pages';
  static const strokes = 'strokes';
}

abstract final class CheckpointKeys {
  static const open = 'open';
}

abstract final class NotebookFields {
  static const id = 0;
  static const name = 1;
  static const inkColorArgb = 2;
  static const createdAt = 3;
  static const updatedAt = 4;
  static const deletedAt = 5;
  static const syncState = 6;
  static const ownerId = 7;
  static const clockFlags = 8;
  static const version = 9;
}

abstract final class PageFields {
  static const id = 0;
  static const notebookId = 1;
  static const pageIndex = 2;
  static const createdAt = 3;
  static const capturedAt = 4;
  static const paperLeft = 5;
  static const paperTop = 6;
  static const paperWidth = 7;
  static const paperHeight = 8;
  static const recognizedText = 9;
  static const markers = 10;
  static const syncState = 11;
  static const ownerId = 12;
  static const deletedAt = 13;
  static const clockFlags = 14;
  static const version = 15;
  static const updatedAt = 16;
}

abstract final class StrokeFields {
  static const id = 0;
  static const pageId = 1;
  static const colorArgb = 2;
  static const width = 3;
  static const createdAt = 4;
  static const updatedAt = 5;
  static const version = 6;
  static const deletedAt = 7;
  static const syncState = 8;
  static const ownerId = 9;
  static const packedPoints = 10;
  static const timeOriginMs = 11;
  static const legacyPoints = 12;
  static const clockFlags = 13;
}

abstract final class PointFields {
  static const xMm = 0;
  static const yMm = 1;
  static const pressure = 2;
  static const flags = 3;
  static const tMs = 4;
}

abstract final class CheckpointFields {
  static const strokeId = 0;
  static const pageId = 1;
  static const colorArgb = 2;
  static const width = 3;
  static const createdAt = 4;
  static const updatedAt = 5;
  static const version = 6;
  static const packedPoints = 7;
  static const timeOriginMs = 8;
  static const syncState = 9;
  static const clockFlags = 10;
}

/// Bit 0 of a packed point's flags.
const int pointFlagTouching = 0x01;

/// Bit 1 of a packed point's flags.
const int pointFlagApproximate = 0x02;
