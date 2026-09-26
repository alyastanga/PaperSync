import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/screens/device_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/cloud.dart';
import 'package:papersync/sync/auth.dart';
import 'package:papersync/theme/app_theme.dart';

void main() {
  testWidgets('the sign-in sheet checks the email and waits 60s to resend', (
    tester,
  ) async {
    final auth = _SheetAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
          paperSyncAuthProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const DeviceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back up notebooks'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter an email address.'), findsOneWidget);
    expect(auth.sends, 0);

    await tester.enterText(find.byType(TextField), 'student@school.edu');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(auth.sends, 1);
    expect(find.text('Resend in 60s'), findsOneWidget);
    expect(auth.lastEmail, 'student@school.edu');
  });
}

class _SheetAuth implements PaperSyncAuth {
  var sends = 0;
  String? lastEmail;

  @override
  SignedInAccount? get current => null;

  @override
  Stream<SignedInAccount?> watchAccount() => const Stream.empty();

  @override
  Future<void> sendEmailCode(String email) async {
    sends += 1;
    lastEmail = email;
  }

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
