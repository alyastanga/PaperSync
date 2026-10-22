import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/storage/sync_ledger.dart';
import 'package:papersync/sync/keyset.dart';

void main() {
  const id = '33333333-3333-4333-8333-333333333333';
  final when = DateTime.utc(2026, 9, 26, 12, 2, 3, 4, 5);

  test('a cursor round-trips with its row id', () {
    final cursor = SyncCursor(updatedAt: when, id: id);
    expect(SyncCursor.decode(cursor.encode()), cursor);
  });

  test('a timestamp cursor from an older install has no row id', () {
    final encoded = when.toIso8601String();
    expect(encoded.contains('|'), isFalse);
    expect(SyncCursor.decode(encoded), SyncCursor(updatedAt: when));
    expect(SyncCursor.decode(''), isNull);
    expect(SyncCursor.decode('not-a-time'), isNull);
  });

  test('the same timestamp stays visible until its id is passed', () {
    final earlier = when.subtract(const Duration(seconds: 1));
    final later = when.add(const Duration(seconds: 1));
    expect(
      isAfterSyncCursor(updatedAt: later, id: 'a', after: when, afterId: id),
      isTrue,
    );
    expect(
      isAfterSyncCursor(updatedAt: earlier, id: 'z', after: when, afterId: id),
      isFalse,
    );
    expect(
      isAfterSyncCursor(updatedAt: when, id: id, after: when, afterId: id),
      isFalse,
    );
    expect(
      isAfterSyncCursor(
        updatedAt: when,
        id: '${id}0',
        after: when,
        afterId: id,
      ),
      isTrue,
    );
    expect(
      isAfterSyncCursor(updatedAt: when, id: '00000000', after: when),
      isTrue,
    );
    expect(isAfterSyncCursor(updatedAt: earlier, id: id, after: null), isTrue);
  });
}
