import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/main.dart';
import 'package:papersync/screens/account_sync_screen.dart';
import 'package:papersync/screens/comic_strip_screen.dart';
import 'package:papersync/screens/settings_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/theme/app_theme.dart';

void main() {
  testWidgets('welcome opens sign-in and does not pretend a password worked', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(
            SimulatedPenTransport(manual: true),
          ),
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
        ],
        child: const PaperSyncApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PaperSync'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter an email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'ada@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.textContaining('password is not sent'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets(
    'create account keeps a name locally and rejects a short password',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            penTransportProvider.overrideWithValue(
              SimulatedPenTransport(manual: true),
            ),
            appControllerProvider.overrideWith(
              () => AppController(AppModel.empty()),
            ),
          ],
          child: const PaperSyncApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Ada');
      await tester.enterText(find.byType(TextField).at(1), 'ada@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Use at least 8 characters.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(2), 'long-enough');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(
        find.textContaining('does not create a cloud account'),
        findsOneWidget,
      );

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(find.text('Handwriting recognition'), findsOneWidget);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSyncScreen), findsOneWidget);
      expect(find.text('On this phone'), findsOneWidget);
      expect(find.text('Last sync: not recorded'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comic strip'));
      await tester.pumpAndSettle();
      expect(find.byType(ComicStripScreen), findsOneWidget);
      expect(find.text('1987 Constitution'), findsOneWidget);
    },
  );

  testWidgets('settings appearance cycles without a backend', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(
            SimulatedPenTransport(manual: true),
          ),
          appControllerProvider.overrideWith(
            () => AppController(AppModel.sample()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('System'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    expect(find.text('Light'), findsOneWidget);
    await tester.tap(find.text('Handwriting recognition'));
    await tester.pump();
    expect(find.text('Off'), findsOneWidget);
  });
}
