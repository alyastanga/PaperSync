import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import 'records.dart';
import 'schema.dart';

void registerStorageAdapters() {
  _register(NotebookAdapter());
  _register(PageAdapter());
  _register(StrokeAdapter());
  _register(PointAdapter());
  _register(CheckpointAdapter());
}

void _register<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter(adapter);
  }
}

void writeFields(BinaryWriter writer, Map<int, Object> fields) {
  final indexes = fields.keys.toList()..sort();
  writer.writeByte(indexes.length);
  for (final index in indexes) {
    writer
      ..writeByte(index)
      ..write(fields[index]);
  }
}

Map<int, Object?> readFields(BinaryReader reader) {
  final count = reader.readByte();
  final fields = <int, Object?>{};
  for (var i = 0; i < count; i++) {
    final index = reader.readByte();
    fields[index] = reader.read() as Object?;
  }
  return fields;
}

class NotebookAdapter extends TypeAdapter<StoredNotebook> {
  @override
  int get typeId => TypeIds.notebook;

  @override
  StoredNotebook read(BinaryReader reader) {
    final fields = readFields(reader);
    return StoredNotebook(
      id: _string(fields[NotebookFields.id]),
      name: _string(fields[NotebookFields.name]),
      inkColorArgb: _int(fields[NotebookFields.inkColorArgb]),
      createdAtUs: _int(fields[NotebookFields.createdAt]),
      updatedAtUs: _int(fields[NotebookFields.updatedAt]),
      deletedAtUs: _optionalInt(fields[NotebookFields.deletedAt]),
      syncState: _int(fields[NotebookFields.syncState]),
      ownerId: _optionalString(fields[NotebookFields.ownerId]),
      clockFlags: _int(fields[NotebookFields.clockFlags]),
      version: _int(fields[NotebookFields.version], fallback: 1),
    );
  }

  @override
  void write(BinaryWriter writer, StoredNotebook obj) {
    writeFields(writer, <int, Object>{
      NotebookFields.id: obj.id,
      NotebookFields.name: obj.name,
      NotebookFields.inkColorArgb: obj.inkColorArgb,
      NotebookFields.createdAt: obj.createdAtUs,
      NotebookFields.updatedAt: obj.updatedAtUs,
      if (obj.deletedAtUs != null) NotebookFields.deletedAt: obj.deletedAtUs!,
      NotebookFields.syncState: obj.syncState,
      if (obj.ownerId != null) NotebookFields.ownerId: obj.ownerId!,
      NotebookFields.clockFlags: obj.clockFlags,
      NotebookFields.version: obj.version,
    });
  }
}

class PageAdapter extends TypeAdapter<StoredPage> {
  @override
  int get typeId => TypeIds.page;

  @override
  StoredPage read(BinaryReader reader) {
    final fields = readFields(reader);
    return StoredPage(
      id: _string(fields[PageFields.id]),
      notebookId: _string(fields[PageFields.notebookId]),
      pageIndex: _int(fields[PageFields.pageIndex]),
      createdAtUs: _int(fields[PageFields.createdAt]),
      capturedAtUs: _int(fields[PageFields.capturedAt]),
      paperLeft: _double(fields[PageFields.paperLeft]),
      paperTop: _double(fields[PageFields.paperTop]),
      paperWidth: _double(fields[PageFields.paperWidth]),
      paperHeight: _double(fields[PageFields.paperHeight]),
      recognizedText: _string(fields[PageFields.recognizedText]),
      markers: _strings(fields[PageFields.markers]),
      syncState: _int(fields[PageFields.syncState]),
      ownerId: _optionalString(fields[PageFields.ownerId]),
      deletedAtUs: _optionalInt(fields[PageFields.deletedAt]),
      clockFlags: _int(fields[PageFields.clockFlags]),
      version: _int(fields[PageFields.version], fallback: 1),
      updatedAtUs: _int(fields[PageFields.updatedAt]),
    );
  }

  @override
  void write(BinaryWriter writer, StoredPage obj) {
    writeFields(writer, <int, Object>{
      PageFields.id: obj.id,
      PageFields.notebookId: obj.notebookId,
      PageFields.pageIndex: obj.pageIndex,
      PageFields.createdAt: obj.createdAtUs,
      PageFields.capturedAt: obj.capturedAtUs,
      PageFields.paperLeft: obj.paperLeft,
      PageFields.paperTop: obj.paperTop,
      PageFields.paperWidth: obj.paperWidth,
      PageFields.paperHeight: obj.paperHeight,
      PageFields.recognizedText: obj.recognizedText,
      PageFields.markers: obj.markers,
      PageFields.syncState: obj.syncState,
      if (obj.ownerId != null) PageFields.ownerId: obj.ownerId!,
      if (obj.deletedAtUs != null) PageFields.deletedAt: obj.deletedAtUs!,
      PageFields.clockFlags: obj.clockFlags,
      PageFields.version: obj.version,
      if (obj.updatedAtUs != 0) PageFields.updatedAt: obj.updatedAtUs,
    });
  }
}

class StrokeAdapter extends TypeAdapter<StoredStroke> {
  @override
  int get typeId => TypeIds.stroke;

  @override
  StoredStroke read(BinaryReader reader) {
    final fields = readFields(reader);
    return StoredStroke(
      id: _string(fields[StrokeFields.id]),
      pageId: _string(fields[StrokeFields.pageId]),
      colorArgb: _int(fields[StrokeFields.colorArgb]),
      width: _double(fields[StrokeFields.width], fallback: 1),
      createdAtUs: _int(fields[StrokeFields.createdAt]),
      updatedAtUs: _int(fields[StrokeFields.updatedAt]),
      version: _int(fields[StrokeFields.version], fallback: 1),
      deletedAtUs: _optionalInt(fields[StrokeFields.deletedAt]),
      syncState: _int(fields[StrokeFields.syncState]),
      ownerId: _optionalString(fields[StrokeFields.ownerId]),
      packedPoints: _bytes(fields[StrokeFields.packedPoints]),
      timeOriginMs: _int(fields[StrokeFields.timeOriginMs]),
      legacyPoints: _points(fields[StrokeFields.legacyPoints]),
      clockFlags: _int(fields[StrokeFields.clockFlags]),
    );
  }

  @override
  void write(BinaryWriter writer, StoredStroke obj) {
    writeFields(writer, <int, Object>{
      StrokeFields.id: obj.id,
      StrokeFields.pageId: obj.pageId,
      StrokeFields.colorArgb: obj.colorArgb,
      StrokeFields.width: obj.width,
      StrokeFields.createdAt: obj.createdAtUs,
      StrokeFields.updatedAt: obj.updatedAtUs,
      StrokeFields.version: obj.version,
      if (obj.deletedAtUs != null) StrokeFields.deletedAt: obj.deletedAtUs!,
      StrokeFields.syncState: obj.syncState,
      if (obj.ownerId != null) StrokeFields.ownerId: obj.ownerId!,
      if (obj.packedPoints != null)
        StrokeFields.packedPoints: obj.packedPoints!,
      StrokeFields.timeOriginMs: obj.timeOriginMs,
      if (obj.legacyPoints != null)
        StrokeFields.legacyPoints: obj.legacyPoints!,
      StrokeFields.clockFlags: obj.clockFlags,
    });
  }
}

class PointAdapter extends TypeAdapter<StoredPoint> {
  @override
  int get typeId => TypeIds.point;

  @override
  StoredPoint read(BinaryReader reader) {
    final fields = readFields(reader);
    return StoredPoint(
      xMm: _double(fields[PointFields.xMm]),
      yMm: _double(fields[PointFields.yMm]),
      pressure: _int(fields[PointFields.pressure]),
      flags: _int(fields[PointFields.flags]),
      tMs: _int(fields[PointFields.tMs]),
    );
  }

  @override
  void write(BinaryWriter writer, StoredPoint obj) {
    writeFields(writer, <int, Object>{
      PointFields.xMm: obj.xMm,
      PointFields.yMm: obj.yMm,
      PointFields.pressure: obj.pressure,
      PointFields.flags: obj.flags,
      PointFields.tMs: obj.tMs,
    });
  }
}

class CheckpointAdapter extends TypeAdapter<StoredCheckpoint> {
  @override
  int get typeId => TypeIds.checkpoint;

  @override
  StoredCheckpoint read(BinaryReader reader) {
    final fields = readFields(reader);
    return StoredCheckpoint(
      strokeId: _string(fields[CheckpointFields.strokeId]),
      pageId: _string(fields[CheckpointFields.pageId]),
      colorArgb: _int(fields[CheckpointFields.colorArgb]),
      width: _double(fields[CheckpointFields.width], fallback: 1),
      createdAtUs: _int(fields[CheckpointFields.createdAt]),
      updatedAtUs: _int(fields[CheckpointFields.updatedAt]),
      version: _int(fields[CheckpointFields.version], fallback: 1),
      packedPoints:
          _bytes(fields[CheckpointFields.packedPoints]) ?? Uint8List(0),
      timeOriginMs: _int(fields[CheckpointFields.timeOriginMs]),
      syncState: _int(fields[CheckpointFields.syncState]),
      clockFlags: _int(fields[CheckpointFields.clockFlags]),
    );
  }

  @override
  void write(BinaryWriter writer, StoredCheckpoint obj) {
    writeFields(writer, <int, Object>{
      CheckpointFields.strokeId: obj.strokeId,
      CheckpointFields.pageId: obj.pageId,
      CheckpointFields.colorArgb: obj.colorArgb,
      CheckpointFields.width: obj.width,
      CheckpointFields.createdAt: obj.createdAtUs,
      CheckpointFields.updatedAt: obj.updatedAtUs,
      CheckpointFields.version: obj.version,
      CheckpointFields.packedPoints: obj.packedPoints,
      CheckpointFields.timeOriginMs: obj.timeOriginMs,
      CheckpointFields.syncState: obj.syncState,
      CheckpointFields.clockFlags: obj.clockFlags,
    });
  }
}

String _string(Object? value) => value is String ? value : '';

String? _optionalString(Object? value) => value is String ? value : null;

int _int(Object? value, {int fallback = 0}) => value is int ? value : fallback;

int? _optionalInt(Object? value) => value is int ? value : null;

double _double(Object? value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return fallback;
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

Uint8List? _bytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  return null;
}

List<StoredPoint>? _points(Object? value) {
  if (value is! List) return null;
  final points = <StoredPoint>[];
  for (final item in value) {
    if (item is StoredPoint) points.add(item);
  }
  return points;
}
