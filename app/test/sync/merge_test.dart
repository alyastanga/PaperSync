import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/sync/backoff.dart';
import 'package:papersync/sync/merge.dart';

void main() {
  final earlier = DateTime.utc(2026, 9, 1);
  final later = DateTime.utc(2026, 9, 2);

  test('merge covers version, time, and tombstones', () {
    expect(
      mergeRecord(
        localVersion: null,
        localUpdatedAt: null,
        localDeleted: false,
        remoteVersion: 1,
        remoteUpdatedAt: earlier,
        remoteDeleted: false,
      ),
      MergeChoice.takeRemote,
    );
    expect(_merge(localVersion: 1, remoteVersion: 2), MergeChoice.takeRemote);
    expect(_merge(localVersion: 3, remoteVersion: 1), MergeChoice.keepLocal);
    expect(
      _merge(localVersion: 2, remoteVersion: 1, remoteDeleted: true),
      MergeChoice.keepLocal,
    );
    expect(
      _merge(localUpdatedAt: earlier, remoteUpdatedAt: later),
      MergeChoice.takeRemote,
    );
    expect(
      _merge(localUpdatedAt: later, remoteUpdatedAt: earlier),
      MergeChoice.keepLocal,
    );
    expect(_merge(remoteDeleted: true), MergeChoice.takeRemote);
    expect(_merge(localDeleted: true), MergeChoice.keepLocal);
    expect(
      _merge(
        localDeleted: true,
        remoteDeleted: true,
        localUpdatedAt: earlier,
        remoteUpdatedAt: later,
      ),
      MergeChoice.takeRemote,
    );
    expect(
      _merge(remoteVersion: 4, remoteDeleted: true, localVersion: 2),
      MergeChoice.takeRemote,
    );
  });

  test('backoff starts at 5 seconds and caps at 5 minutes', () {
    expect(syncBackoff(1), const Duration(seconds: 5));
    expect(syncBackoff(2), const Duration(seconds: 10));
    expect(syncBackoff(3), const Duration(seconds: 20));
    expect(syncBackoff(7), const Duration(minutes: 5));
    expect(syncBackoff(8), const Duration(minutes: 5));
    expect(
      syncBackoff(1, jitterMs: 250),
      const Duration(seconds: 5, milliseconds: 250),
    );
  });
}

MergeChoice _merge({
  int localVersion = 1,
  int remoteVersion = 1,
  DateTime? localUpdatedAt,
  DateTime? remoteUpdatedAt,
  bool localDeleted = false,
  bool remoteDeleted = false,
}) {
  return mergeRecord(
    localVersion: localVersion,
    localUpdatedAt: localUpdatedAt ?? DateTime.utc(2026, 9, 1),
    localDeleted: localDeleted,
    remoteVersion: remoteVersion,
    remoteUpdatedAt: remoteUpdatedAt ?? DateTime.utc(2026, 9, 1),
    remoteDeleted: remoteDeleted,
  );
}
