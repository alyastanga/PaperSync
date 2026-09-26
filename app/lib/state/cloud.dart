import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/connectivity_watch.dart';
import '../sync/auth.dart';
import '../sync/backoff.dart';
import '../sync/failure.dart';
import '../sync/remote.dart';
import '../sync/sync_service.dart';
import 'flutter_test_env.dart';
import 'notebook_store_provider.dart';

final paperSyncAuthProvider = Provider<PaperSyncAuth>((ref) {
  return const DisabledAuth();
});

final notebookRemoteProvider = Provider<NotebookRemote?>((ref) => null);

final syncServiceProvider = Provider<SyncService?>((ref) {
  final remote = ref.watch(notebookRemoteProvider);
  if (remote == null) return null;
  return SyncService(
    ledger: ref.watch(notebookStoreProvider),
    remote: remote,
    auth: ref.watch(paperSyncAuthProvider),
  );
});

final syncStatusProvider = StateProvider<SyncStatus>((ref) => const SyncIdle());

final backupReadyProvider = Provider<bool>((ref) {
  return ref.watch(paperSyncAuthProvider) is! DisabledAuth;
});

final backupNoticeProvider = Provider<String?>((ref) {
  final status = ref.watch(syncStatusProvider);
  if (status is SyncFailed) return backupFailedCopy;
  return null;
});

/// Starts a backup after a local write, when the app resumes, and again
/// after a failure. Signed-out installs do nothing.
class SyncCoordinator {
  SyncCoordinator(this._ref, {Stream<void>? connectivityRegained}) {
    final auth = _ref.read(paperSyncAuthProvider);
    _accountSub = auth.watchAccount().listen(
      _onAccount,
      onError: (Object _) {},
    );
    _notesSub = _ref.read(notebookStoreProvider).watchNotebooks().listen((_) {
      _scheduleAfterWrite();
    });
    final current = auth.current;
    if (current != null) {
      unawaited(_onAccount(current));
    }
    if (connectivityRegained != null) {
      _onlineSub = connectivityRegained.listen(
        (_) => unawaited(syncNow()),
        onError: (Object _) {},
      );
    }
  }

  final Ref _ref;
  StreamSubscription<SignedInAccount?>? _accountSub;
  StreamSubscription<Object?>? _notesSub;
  StreamSubscription<void>? _onlineSub;
  Timer? _debounce;
  Timer? _retry;
  int _failures = 0;
  bool _applyingAccount = false;
  final Random _random = Random();

  void onResume() {
    unawaited(syncNow());
  }

  Future<void> syncNow() async {
    final service = _ref.read(syncServiceProvider);
    final account = _ref.read(paperSyncAuthProvider).current;
    if (service == null || account == null) return;
    _retry?.cancel();
    _ref.read(syncStatusProvider.notifier).state = const SyncSyncing();
    final status = await service.run();
    _ref.read(syncStatusProvider.notifier).state = status;
    if (status is SyncFailed &&
        (status.reason is ServerError || status.reason is Offline)) {
      _failures += 1;
      _retry = Timer(
        syncBackoff(_failures, jitterMs: _random.nextInt(1000)),
        () {
          unawaited(syncNow());
        },
      );
      return;
    }
    if (status is SyncIdle) _failures = 0;
  }

  void _scheduleAfterWrite() {
    if (_applyingAccount) return;
    if (_ref.read(paperSyncAuthProvider).current == null) return;
    if (_ref.read(syncServiceProvider)?.isRunning ?? false) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () {
      unawaited(syncNow());
    });
  }

  Future<void> _onAccount(SignedInAccount? account) async {
    _applyingAccount = true;
    try {
      final store = _ref.read(notebookStoreProvider);
      if (account == null) {
        _debounce?.cancel();
        _retry?.cancel();
        await store.adoptUser(null);
        _ref.read(syncStatusProvider.notifier).state = const SyncIdle();
        return;
      }
      await store.claimUnowned(account.id);
      await store.rememberHomeUser(account.id);
      await store.adoptUser(account.id);
    } finally {
      _applyingAccount = false;
    }
    await syncNow();
  }

  void dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    unawaited(_accountSub?.cancel());
    unawaited(_notesSub?.cancel());
    unawaited(_onlineSub?.cancel());
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    ref,
    connectivityRegained: isFlutterTest ? null : connectivityRegained(),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
