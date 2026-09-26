import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/screens/account_sync_screen.dart';
import 'package:papersync/screens/comic_strip_screen.dart';
import 'package:papersync/screens/create_account_screen.dart';
import 'package:papersync/screens/device_screen.dart';
import 'package:papersync/screens/library_screen.dart';
import 'package:papersync/screens/live_capture_screen.dart';
import 'package:papersync/screens/notebook_pages_screen.dart';
import 'package:papersync/screens/page_editor_screen.dart';
import 'package:papersync/screens/reset_password_screen.dart';
import 'package:papersync/screens/search_screen.dart';
import 'package:papersync/screens/settings_screen.dart';
import 'package:papersync/screens/sign_in_screen.dart';
import 'package:papersync/screens/sync_issue_screen.dart';
import 'package:papersync/screens/welcome_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/cloud.dart';
import 'package:papersync/state/notebook_store_provider.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/state/ui_preferences.dart';
import 'package:papersync/storage/schema.dart';
import 'package:papersync/sync/auth.dart';
import 'package:papersync/sync/failure.dart';
import 'package:papersync/theme/app_theme.dart';
import 'package:papersync/theme/tokens.dart';

import 'fixtures.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader(PaperTokens.fontFamily);
    for (final file in [
      'Inter-Regular.ttf',
      'Inter-Medium.ttf',
      'Inter-SemiBold.ttf',
    ]) {
      final data = await rootBundle.load('assets/fonts/$file');
      loader.addFont(Future<ByteData>.value(data));
    }
    await loader.load();
  });

  final cases = <_Case>[
    _Case('library', const LibraryScreen(), libraryModel()),
    _Case('library_empty', const LibraryScreen(), emptyModel()),
    _Case(
      'library_error',
      const LibraryScreen(),
      libraryModel(),
      storageNotice: storageQuarantineNotice,
    ),
    _Case(
      'library_backup_failed',
      const LibraryScreen(),
      libraryModel(),
      syncFailed: true,
    ),
    _Case(
      'notebook',
      NotebookPagesScreen(notebookId: libraryModel().notebooks.first.id),
      libraryModel(),
    ),
    _Case(
      'live_capture',
      LiveCaptureScreen(notebookId: libraryModel().notebooks.first.id),
      libraryModel(),
    ),
    _Case(
      'page_editor',
      PageEditorScreen(
        notebookId: libraryModel().notebooks.first.id,
        pageId: 'page-lecture-3',
      ),
      libraryModel(),
    ),
    _Case('pen', const DeviceScreen(), libraryModel()),
    _Case('pen_setup', const DeviceScreen(), emptyModel()),
    _Case(
      'pen_nearby',
      const DeviceScreen(),
      emptyModel(permissionGranted: true),
    ),
    _Case(
      'search_results',
      const SearchScreen(),
      libraryModel(),
      query: 'friction',
    ),
    _Case('search_none', const SearchScreen(), emptyModel()),
    _Case(
      'search_no_match',
      const SearchScreen(),
      libraryModel(),
      query: 'zzzz',
    ),
    _Case('sign_in', const DeviceScreen(), emptyModel(), signIn: true),
    _Case(
      'sync_issue',
      const SyncIssueScreen(),
      libraryModel(),
      syncFailed: true,
    ),
    _Case('welcome', WelcomeScreen(onContinue: () {}), emptyModel()),
    _Case('sign_in_form', const SignInScreen(), emptyModel()),
    _Case('create_account', const CreateAccountScreen(), emptyModel()),
    _Case('reset_password', const ResetPasswordScreen(), emptyModel()),
    _Case('settings', const SettingsScreen(), libraryModel(), profile: true),
    _Case(
      'account_sync',
      const AccountSyncScreen(),
      libraryModel(),
      profile: true,
    ),
    _Case('comic_strip', const ComicStripScreen(), emptyModel()),
  ];

  for (final item in cases) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';
      testWidgets('${item.name} $suffix', (tester) async {
        await _show(tester, item, mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${item.name}_$suffix.png'),
        );
      });
    }
  }
}

class _Case {
  const _Case(
    this.name,
    this.home,
    this.model, {
    this.storageNotice,
    this.syncFailed = false,
    this.query,
    this.signIn = false,
    this.profile = false,
  });

  final String name;
  final Widget home;
  final AppModel model;
  final String? storageNotice;
  final bool syncFailed;
  final String? query;
  final bool signIn;
  final bool profile;
}

Future<void> _show(WidgetTester tester, _Case item, ThemeMode mode) async {
  tester.view.physicalSize = const Size(
    PaperTokens.frameWidth,
    PaperTokens.frameHeight,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        penTransportProvider.overrideWithValue(
          SimulatedPenTransport(
            manual: true,
            clock: () => DateTime.utc(2026, 9, 26),
          ),
        ),
        appControllerProvider.overrideWith(() => AppController(item.model)),
        if (item.storageNotice != null)
          storageNoticeProvider.overrideWithValue(item.storageNotice),
        if (item.syncFailed)
          syncStatusProvider.overrideWith((ref) => const SyncFailed(Offline())),
        if (item.signIn)
          paperSyncAuthProvider.overrideWithValue(const _OpenAuth()),
        if (item.profile) uiPreferencesProvider.overrideWith(_PeterPrefs.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: item.home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final query = item.query;
  if (query != null) {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }
  if (item.signIn) {
    await tester.tap(find.text('Back up notebooks'));
    await tester.pumpAndSettle();
  }
}

class _PeterPrefs extends UiPreferencesController {
  @override
  UiPreferences build() {
    return const UiPreferences(
      displayName: 'Peter',
      email: 'peter@example.com',
    );
  }
}

class _OpenAuth implements PaperSyncAuth {
  const _OpenAuth();

  @override
  SignedInAccount? get current => null;

  @override
  Stream<SignedInAccount?> watchAccount() => const Stream.empty();

  @override
  Future<void> sendEmailCode(String email) async {}

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<bool> refreshSession() async => false;

  @override
  Future<void> signOut() async {}
}
