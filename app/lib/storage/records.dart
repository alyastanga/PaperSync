import 'dart:typed_data';

import '../domain/ink.dart';
import 'points.dart';

/// A point stored by schema version 1, before points were packed.
class StoredPoint {
  const StoredPoint({
    required this.xMm,
    required this.yMm,
    required this.pressure,
    required this.flags,
    required this.tMs,
  });

  final double xMm;
  final double yMm;
  final int pressure;
  final int flags;
  final int tMs;
}

class StoredNotebook {
  const StoredNotebook({
    required this.id,
    required this.name,
    required this.inkColorArgb,
    required this.createdAtUs,
    required this.updatedAtUs,
    required this.syncState,
    this.deletedAtUs,
    this.ownerId,
    this.clockFlags = 0,
    this.version = 1,
  });

  final String id;
  final String name;
  final int inkColorArgb;
  final int createdAtUs;
  final int updatedAtUs;
  final int? deletedAtUs;
  final int syncState;
  final String? ownerId;
  final int clockFlags;
  final int version;

  static StoredNotebook fromDomain(Notebook notebook, {String? ownerId}) {
    return StoredNotebook(
      id: notebook.id,
      name: notebook.name,
      inkColorArgb: notebook.inkColorArgb,
      createdAtUs: notebook.createdAt.microsecondsSinceEpoch,
      updatedAtUs: notebook.updatedAt.microsecondsSinceEpoch,
      deletedAtUs: notebook.deletedAt?.microsecondsSinceEpoch,
      syncState: _sync(notebook.syncState),
      ownerId: ownerId,
      clockFlags: clockFlagsFor(
        created: notebook.createdAt,
        updated: notebook.updatedAt,
        deleted: notebook.deletedAt,
      ),
      version: notebook.version,
    );
  }

  StoredNotebook copyWith({int? syncState, String? ownerId, int? version}) {
    return StoredNotebook(
      id: id,
      name: name,
      inkColorArgb: inkColorArgb,
      createdAtUs: createdAtUs,
      updatedAtUs: updatedAtUs,
      deletedAtUs: deletedAtUs,
      syncState: syncState ?? this.syncState,
      ownerId: ownerId ?? this.ownerId,
      clockFlags: clockFlags,
      version: version ?? this.version,
    );
  }
}

class StoredPage {
  const StoredPage({
    required this.id,
    required this.notebookId,
    required this.pageIndex,
    required this.createdAtUs,
    required this.capturedAtUs,
    required this.paperLeft,
    required this.paperTop,
    required this.paperWidth,
    required this.paperHeight,
    required this.recognizedText,
    required this.markers,
    required this.syncState,
    this.deletedAtUs,
    this.ownerId,
    this.clockFlags = 0,
    this.version = 1,
    this.updatedAtUs = 0,
  });

  final String id;
  final String notebookId;
  final int pageIndex;
  final int createdAtUs;
  final int capturedAtUs;
  final double paperLeft;
  final double paperTop;
  final double paperWidth;
  final double paperHeight;
  final String recognizedText;
  final List<String> markers;
  final int? deletedAtUs;
  final int syncState;
  final String? ownerId;
  final int clockFlags;
  final int version;
  final int updatedAtUs;

  static StoredPage fromDomain(
    NotebookPage page, {
    String? ownerId,
    int? deletedAtUs,
  }) {
    return StoredPage(
      id: page.id,
      notebookId: page.notebookId,
      pageIndex: page.pageIndex,
      createdAtUs: page.createdAt.microsecondsSinceEpoch,
      capturedAtUs: page.capturedAt.microsecondsSinceEpoch,
      paperLeft: page.paperRect.leftMm,
      paperTop: page.paperRect.topMm,
      paperWidth: page.paperRect.widthMm,
      paperHeight: page.paperRect.heightMm,
      recognizedText: page.recognizedText,
      markers: page.markers,
      deletedAtUs: deletedAtUs,
      syncState: _sync(page.syncState),
      ownerId: ownerId,
      clockFlags: clockFlagsFor(
        created: page.createdAt,
        updated: page.updatedAt,
        captured: page.capturedAt,
        deleted: page.deletedAt,
      ),
      version: page.version,
      updatedAtUs: page.updatedAt.microsecondsSinceEpoch,
    );
  }

  StoredPage copyWith({
    int? deletedAtUs,
    int? syncState,
    String? ownerId,
    int? version,
    int? updatedAtUs,
  }) {
    return StoredPage(
      id: id,
      notebookId: notebookId,
      pageIndex: pageIndex,
      createdAtUs: createdAtUs,
      capturedAtUs: capturedAtUs,
      paperLeft: paperLeft,
      paperTop: paperTop,
      paperWidth: paperWidth,
      paperHeight: paperHeight,
      recognizedText: recognizedText,
      markers: markers,
      deletedAtUs: deletedAtUs ?? this.deletedAtUs,
      syncState: syncState ?? this.syncState,
      ownerId: ownerId ?? this.ownerId,
      clockFlags: clockFlags,
      version: version ?? this.version,
      updatedAtUs: updatedAtUs ?? this.updatedAtUs,
    );
  }
}

class StoredStroke {
  const StoredStroke({
    required this.id,
    required this.pageId,
    required this.colorArgb,
    required this.width,
    required this.createdAtUs,
    required this.updatedAtUs,
    required this.version,
    required this.syncState,
    required this.timeOriginMs,
    this.deletedAtUs,
    this.ownerId,
    this.packedPoints,
    this.legacyPoints,
    this.clockFlags = 0,
  });

  final String id;
  final String pageId;
  final int colorArgb;
  final double width;
  final int createdAtUs;
  final int updatedAtUs;
  final int version;
  final int? deletedAtUs;
  final int syncState;
  final String? ownerId;
  final Uint8List? packedPoints;
  final int timeOriginMs;
  final List<StoredPoint>? legacyPoints;
  final int clockFlags;

  static StoredStroke fromDomain(
    String pageId,
    Stroke stroke, {
    String? ownerId,
    bool forcePending = true,
  }) {
    final packed = packPoints(stroke.points);
    return StoredStroke(
      id: stroke.id,
      pageId: pageId,
      colorArgb: stroke.colorArgb,
      width: stroke.width,
      createdAtUs: stroke.createdAt.microsecondsSinceEpoch,
      updatedAtUs: stroke.updatedAt.microsecondsSinceEpoch,
      version: stroke.version,
      deletedAtUs: stroke.deletedAt?.microsecondsSinceEpoch,
      syncState: _sync(forcePending ? SyncState.pending : stroke.syncState),
      ownerId: ownerId,
      packedPoints: packed.bytes,
      timeOriginMs: packed.timeOriginMs,
      clockFlags: clockFlagsFor(
        created: stroke.createdAt,
        updated: stroke.updatedAt,
        deleted: stroke.deletedAt,
      ),
    );
  }

  StoredStroke copyWith({
    Uint8List? packedPoints,
    int? timeOriginMs,
    List<StoredPoint>? legacyPoints,
    bool clearLegacy = false,
  }) {
    return StoredStroke(
      id: id,
      pageId: pageId,
      colorArgb: colorArgb,
      width: width,
      createdAtUs: createdAtUs,
      updatedAtUs: updatedAtUs,
      version: version,
      deletedAtUs: deletedAtUs,
      syncState: syncState,
      ownerId: ownerId,
      packedPoints: packedPoints ?? this.packedPoints,
      timeOriginMs: timeOriginMs ?? this.timeOriginMs,
      legacyPoints: clearLegacy ? null : (legacyPoints ?? this.legacyPoints),
      clockFlags: clockFlags,
    );
  }

  Stroke toDomain() {
    final points = unpackPoints(packedPoints ?? Uint8List(0), timeOriginMs);
    return Stroke(
      id: id,
      points: points,
      colorArgb: colorArgb,
      width: width,
      createdAt: clockTime(createdAtUs, clockFlags, clockCreatedUtc),
      updatedAt: clockTime(updatedAtUs, clockFlags, clockUpdatedUtc),
      version: version < 1 ? 1 : version,
      deletedAt: deletedAtUs == null
          ? null
          : clockTime(deletedAtUs!, clockFlags, clockDeletedUtc),
      syncState: _decodeSync(syncState),
    );
  }
}

class StoredCheckpoint {
  const StoredCheckpoint({
    required this.strokeId,
    required this.pageId,
    required this.colorArgb,
    required this.width,
    required this.createdAtUs,
    required this.updatedAtUs,
    required this.version,
    required this.packedPoints,
    required this.timeOriginMs,
    required this.syncState,
    this.clockFlags = 0,
  });

  final String strokeId;
  final String pageId;
  final int colorArgb;
  final double width;
  final int createdAtUs;
  final int updatedAtUs;
  final int version;
  final Uint8List packedPoints;
  final int timeOriginMs;
  final int syncState;
  final int clockFlags;

  static StoredCheckpoint fromStroke(String pageId, Stroke stroke) {
    final stored = StoredStroke.fromDomain(pageId, stroke);
    return StoredCheckpoint(
      strokeId: stored.id,
      pageId: pageId,
      colorArgb: stored.colorArgb,
      width: stored.width,
      createdAtUs: stored.createdAtUs,
      updatedAtUs: stored.updatedAtUs,
      version: stored.version,
      packedPoints: stored.packedPoints ?? Uint8List(0),
      timeOriginMs: stored.timeOriginMs,
      syncState: stored.syncState,
      clockFlags: stored.clockFlags,
    );
  }

  StoredStroke toStroke() {
    return StoredStroke(
      id: strokeId,
      pageId: pageId,
      colorArgb: colorArgb,
      width: width,
      createdAtUs: createdAtUs,
      updatedAtUs: updatedAtUs,
      version: version,
      syncState: _sync(SyncState.pending),
      packedPoints: packedPoints,
      timeOriginMs: timeOriginMs,
      clockFlags: clockFlags,
    );
  }
}

const int clockCreatedUtc = 1;
const int clockUpdatedUtc = 2;
const int clockDeletedUtc = 4;
const int clockCapturedUtc = 8;

int clockFlagsFor({
  required DateTime created,
  DateTime? updated,
  DateTime? deleted,
  DateTime? captured,
}) {
  var flags = 0;
  if (created.isUtc) flags |= clockCreatedUtc;
  if (updated != null && updated.isUtc) flags |= clockUpdatedUtc;
  if (deleted != null && deleted.isUtc) flags |= clockDeletedUtc;
  if (captured != null && captured.isUtc) flags |= clockCapturedUtc;
  return flags;
}

DateTime clockTime(int microseconds, int flags, int bit) {
  return DateTime.fromMicrosecondsSinceEpoch(
    microseconds,
    isUtc: flags & bit != 0,
  );
}

int _sync(SyncState state) => state == SyncState.synced ? 1 : 0;

SyncState _decodeSync(int value) =>
    value == 1 ? SyncState.synced : SyncState.pending;
