import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ink.dart';
import '../storage/schema.dart';
import '../storage/sync_ledger.dart';
import '../sync/failure.dart';
import '../sync/remote.dart';

class SupabaseNotebookRemote implements NotebookRemote {
  SupabaseNotebookRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsertNotebooks(List<NotebookSyncRow> rows) {
    return _upsert(SyncTables.notebooks, rows, (row) {
      return {
        'id': row.id,
        'user_id': row.ownerId,
        'name': row.name,
        'ink_color': row.inkColorArgb,
        'version': row.version,
        'created_at': row.createdAt.toUtc().toIso8601String(),
        'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
      };
    });
  }

  @override
  Future<void> upsertPages(List<PageSyncRow> rows) {
    return _upsert(SyncTables.pages, rows, (row) {
      return {
        'id': row.id,
        'notebook_id': row.notebookId,
        'user_id': row.ownerId,
        'page_index': row.pageIndex,
        'version': row.version,
        'captured_at': row.capturedAt.toUtc().toIso8601String(),
        'created_at': row.createdAt.toUtc().toIso8601String(),
        'paper_rect': {
          'leftMm': row.paperLeft,
          'topMm': row.paperTop,
          'widthMm': row.paperWidth,
          'heightMm': row.paperHeight,
        },
        'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
      };
    });
  }

  @override
  Future<void> upsertStrokes(List<StrokeSyncRow> rows) {
    return _upsert(SyncTables.strokes, rows, (row) {
      return {
        'id': row.id,
        'page_id': row.pageId,
        'user_id': row.ownerId,
        // A plain base64 string is stored as those characters. Postgres hex
        // is the form PostgREST writes into bytea.
        'points': _hexBytes(row.points),
        'time_origin_ms': row.timeOriginMs,
        'color': row.colorArgb,
        'width': row.width,
        'version': row.version,
        'created_at': row.createdAt.toUtc().toIso8601String(),
        'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
      };
    });
  }

  @override
  Future<List<NotebookSyncRow>> pullNotebooks({
    DateTime? after,
    int limit = 500,
  }) async {
    final rows = await _pull(SyncTables.notebooks, after, limit);
    return [
      for (final row in rows)
        NotebookSyncRow(
          id: _string(row['id']),
          name: _string(row['name']),
          inkColorArgb: _int(row['ink_color']),
          version: _int(row['version']),
          createdAt: _time(row['created_at']),
          updatedAt: _time(row['updated_at']),
          deletedAt: _optionalTime(row['deleted_at']),
          syncState: SyncState.synced,
          ownerId: _optionalString(row['user_id']),
        ),
    ];
  }

  @override
  Future<List<PageSyncRow>> pullPages({
    DateTime? after,
    int limit = 500,
  }) async {
    final rows = await _pull(SyncTables.pages, after, limit);
    return [
      for (final row in rows)
        PageSyncRow(
          id: _string(row['id']),
          notebookId: _string(row['notebook_id']),
          pageIndex: _int(row['page_index']),
          paperLeft: _paper(row['paper_rect'], 'leftMm', 'originXMm'),
          paperTop: _paper(row['paper_rect'], 'topMm', 'originYMm'),
          paperWidth: _paper(row['paper_rect'], 'widthMm', 'widthMm'),
          paperHeight: _paper(row['paper_rect'], 'heightMm', 'heightMm'),
          recognizedText: '',
          markers: const [],
          version: _int(row['version']),
          createdAt: _time(row['created_at']),
          capturedAt: _time(row['captured_at']),
          updatedAt: _time(row['updated_at']),
          deletedAt: _optionalTime(row['deleted_at']),
          syncState: SyncState.synced,
          ownerId: _optionalString(row['user_id']),
        ),
    ];
  }

  @override
  Future<List<StrokeSyncRow>> pullStrokes({
    DateTime? after,
    int limit = 500,
  }) async {
    final rows = await _pull(SyncTables.strokes, after, limit);
    return [
      for (final row in rows)
        StrokeSyncRow(
          id: _string(row['id']),
          pageId: _string(row['page_id']),
          colorArgb: _int(row['color']),
          width: _double(row['width']),
          version: _int(row['version']),
          createdAt: _time(row['created_at']),
          updatedAt: _time(row['updated_at']),
          deletedAt: _optionalTime(row['deleted_at']),
          syncState: SyncState.synced,
          ownerId: _optionalString(row['user_id']),
          points: _bytes(row['points']),
          timeOriginMs: _int(row['time_origin_ms']),
        ),
    ];
  }

  Future<void> _upsert<T>(
    String table,
    List<T> rows,
    Map<String, Object?> Function(T row) encode,
  ) async {
    if (rows.isEmpty) return;
    try {
      await _client.from(table).upsert([for (final row in rows) encode(row)]);
    } on PostgrestException {
      for (final row in rows) {
        try {
          await _client.from(table).upsert([encode(row)]);
        } on Object catch (error) {
          throw _failure(error, table, _idOf(encode(row)));
        }
      }
    } on Object catch (error) {
      throw _failure(error, table, _idOf(encode(rows.first)));
    }
  }

  Future<List<Map<String, Object?>>> _pull(
    String table,
    DateTime? after,
    int limit,
  ) async {
    try {
      final query = _client.from(table).select();
      final filtered = after == null
          ? query
          : query.gt('updated_at', after.toUtc().toIso8601String());
      final rows = await filtered
          .order('updated_at', ascending: true)
          .limit(limit);
      return [
        for (final row in rows)
          {for (final entry in row.entries) entry.key: entry.value},
      ];
    } on Object catch (error) {
      throw _failure(error, table, '');
    }
  }
}

SyncFailure _failure(Object error, String table, String id) {
  if (error is SyncFailure) return error;
  if (error is AuthRetryableFetchException || _isOffline(error)) {
    return const Offline();
  }
  if (error is AuthException) return const AuthExpired();
  if (error is PostgrestException) {
    final code = error.code ?? '';
    if (code == 'PGRST301' || code == '401') return const AuthExpired();
    // 23xxx is an integrity constraint. P0001 is the version / user_id trigger.
    if (code.startsWith('23') || code == '42501' || code == 'P0001') {
      return Rejected(table: table, id: id);
    }
  }
  return const ServerError();
}

bool _isOffline(Object error) {
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Network is unreachable');
}

String _idOf(Map<String, Object?> row) {
  final id = row['id'];
  return id is String ? id : '';
}

String _string(Object? value) => value is String ? value : '';

String? _optionalString(Object? value) => value is String ? value : null;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return 1;
}

DateTime _time(Object? value) {
  if (value is String) return DateTime.parse(value).toUtc();
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

DateTime? _optionalTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.parse(value).toUtc();
}

double _paper(Object? value, String key, String alternate) {
  if (value is! Map) {
    return key == 'widthMm' ? 170 : (key == 'heightMm' ? 107 : 0);
  }
  final direct = value[key];
  final fallback = value[alternate];
  final picked = direct ?? fallback;
  if (picked is num) return picked.toDouble();
  return 0;
}

String _hexBytes(Uint8List bytes) {
  final hex = StringBuffer(r'\x');
  for (final byte in bytes) {
    hex.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return hex.toString();
}

Uint8List _bytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List) {
    return Uint8List.fromList([
      for (final item in value)
        if (item is int) item,
    ]);
  }
  if (value is String) {
    if (value.startsWith(r'\x')) {
      final hex = value.substring(2);
      final out = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }
    try {
      return Uint8List.fromList(base64Decode(value));
    } on FormatException {
      return Uint8List(0);
    }
  }
  return Uint8List(0);
}
