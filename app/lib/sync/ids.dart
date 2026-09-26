final RegExp _syncUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Client ids are UUID primary keys so a retried push cannot duplicate a row.
bool isSyncUuid(String id) => _syncUuid.hasMatch(id);
