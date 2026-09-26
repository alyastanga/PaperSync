import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/format/labels.dart';
import 'package:papersync/main.dart';
import 'package:papersync/theme/app_theme.dart';
import 'package:papersync/models/ink_models.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/notebook_store_provider.dart';
import 'package:papersync/storage/schema.dart';
import 'package:papersync/widgets/ink_page.dart';

Future<void> _enterLibrary(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final skip = find.text('Continue without account');
  if (skip.evaluate().isNotEmpty) {
    await tester.tap(skip);
    await tester.pumpAndSettle();
  }
}

void main() {
  test('status copy names the link in plain language', () {
    final saving = PenLink.paired();
    expect(statusSentence(saving), 'Saving · 76% battery');

    final reconnecting = saving.copyWith(
      state: LinkState.reconnecting,
      queuedStrokes: 12,
    );
    expect(
      statusSentence(reconnecting),
      'Reconnecting · 12 strokes on the pen · 76% battery',
    );

    final lost = saving.copyWith(
      state: LinkState.disconnected,
      lastSaved: DateTime(2026, 9, 25, 14, 14),
    );
    expect(statusSentence(lost), 'Not connected · last saved 2:14 PM');
  });

  testWidgets('ink page keeps the tablet aspect ratio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Center(
          child: SizedBox(width: 340, child: InkPage(strokes: [])),
        ),
      ),
    );
    final size = tester.getSize(find.byType(InkPage));
    expect(size.width / size.height, closeTo(pageAspect, 0.01));
  });

  testWidgets('library opens a notebook, the editor, and search', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PaperSyncApp()));
    await _enterLibrary(tester);

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Saving'), findsOneWidget);
    expect(find.text('Lecture notes'), findsOneWidget);

    await tester.tap(find.text('Lecture notes'));
    await tester.pumpAndSettle();
    expect(find.text('Live page'), findsOneWidget);

    await tester.tap(find.textContaining('Page 3'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-cluster')), findsOneWidget);
    expect(find.byKey(const Key('stroke-tools')), findsOneWidget);
    expect(find.byKey(const Key('ink-dots')), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Erase'), findsOneWidget);

    await tester.tap(find.byTooltip('Page actions'));
    await tester.pumpAndSettle();
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Export image'), findsOneWidget);
    expect(find.text('Delete page'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('New page'), 400);
    expect(find.text('New page'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'friction');
    await tester.pump();
    expect(find.text('kinetic friction on the ramp'), findsOneWidget);
    expect(find.text('Lecture notes'), findsOneWidget);
  });

  testWidgets('an empty library offers one action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
        ],
        child: const PaperSyncApp(),
      ),
    );
    await _enterLibrary(tester);

    expect(find.text('Pair your pen'), findsOneWidget);
    expect(find.text('New notebook'), findsNothing);

    await tester.tap(find.text('Pair your pen'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on your PaperSync pen'), findsOneWidget);
    expect(find.text('Allow Bluetooth'), findsOneWidget);

    await tester.tap(find.text('Allow Bluetooth'));
    await tester.pumpAndSettle();
    expect(find.text('PaperSync Pen'), findsOneWidget);
  });

  testWidgets('a quarantined box tells the reader a copy was kept', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageNoticeProvider.overrideWithValue(storageQuarantineNotice),
        ],
        child: const PaperSyncApp(),
      ),
    );
    await _enterLibrary(tester);
    expect(find.text(storageQuarantineNotice), findsOneWidget);
  });

  testWidgets('disconnect and forget regroup the pen controls', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PaperSyncApp()));
    await _enterLibrary(tester);

    await tester.tap(find.byKey(const Key('status-pill')));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Forget'), findsOneWidget);
    expect(find.text('Connection details'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.textContaining('Reconnecting'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('Saving'), findsWidgets);
  });
}
