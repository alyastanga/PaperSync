import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/sample_notebooks.dart';
import 'platform/cloud_config.dart';
import 'platform/secure_key_store.dart';
import 'platform/secure_session_storage.dart';
import 'platform/supabase_auth.dart';
import 'platform/supabase_remote.dart';
import 'screens/library_screen.dart';
import 'state/app_controller.dart';
import 'state/cloud.dart';
import 'state/notebook_store_provider.dart';
import 'storage/checkpoint_scheduler.dart';
import 'storage/key_store.dart';
import 'storage/notebook_store.dart';
import 'storage/schema.dart';
import 'storage/session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final session = await _openStorage();
  final overrides = <Override>[
    notebookStoreProvider.overrideWithValue(session.store),
    storageNoticeProvider.overrideWithValue(session.notice),
  ];
  final config = CloudConfig.fromEnvironment;
  if (config.enabled) {
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.anonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
        pkceAsyncStorage: SecureGotrueStorage(),
      ),
    );
    final client = Supabase.instance.client;
    overrides.add(
      paperSyncAuthProvider.overrideWithValue(SupabasePaperSyncAuth(client)),
    );
    overrides.add(
      notebookRemoteProvider.overrideWithValue(SupabaseNotebookRemote(client)),
    );
  }
  runApp(ProviderScope(overrides: overrides, child: const PaperSyncApp()));
}

Future<StorageSession> _openStorage() async {
  try {
    if (kIsWeb) {
      return await openPaperSyncStorage(
        keyStore: MemoryKeyStore(),
        directory: null,
        encrypt: false,
        seed: kDebugMode ? sampleNotebooks() : const [],
      );
    }
    final root = await getApplicationDocumentsDirectory();
    return await openPaperSyncStorage(
      keyStore: SecureHiveKeyStore(),
      directory: '${root.path}/papersync',
      encrypt: true,
      seed: kDebugMode ? sampleNotebooks() : const [],
    );
  } on Object {
    return StorageSession(
      store: MemoryNotebookStore(
        notebooks: kDebugMode ? sampleNotebooks() : const [],
      ),
      notice: storageQuarantineNotice,
    );
  }
}

class PaperSyncApp extends StatelessWidget {
  const PaperSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaperSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _Home(),
    );
  }
}

/// Keeps the open stroke on disk when the phone backgrounds the app.
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncCoordinatorProvider).onResume();
    }
    if (!flushesCheckpoint(state.name)) return;
    unawaited(ref.read(appControllerProvider.notifier).flushOpenStroke());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncCoordinatorProvider);
    return const LibraryScreen();
  }
}
