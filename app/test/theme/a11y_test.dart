import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/screens/device_screen.dart';
import 'package:papersync/screens/library_screen.dart';
import 'package:papersync/screens/notebook_pages_screen.dart';
import 'package:papersync/screens/page_editor_screen.dart';
import 'package:papersync/screens/sync_issue_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/cloud.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/sync/failure.dart';
import 'package:papersync/theme/app_theme.dart';
import 'package:papersync/theme/tokens.dart';

import '../golden/fixtures.dart';

void main() {
  test('text colors clear WCAG AA on their surfaces', () {
    expect(
      _contrast(PaperTokens.lightMeta, PaperTokens.lightCanvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightMeta, PaperTokens.lightPage),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightInk, PaperTokens.lightPage),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightInk, PaperTokens.lightCanvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightOnAccent, PaperTokens.lightInk),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightDanger, PaperTokens.lightCanvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightOnAccent, PaperTokens.lightDanger),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.darkMeta, PaperTokens.darkCanvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.darkMeta, PaperTokens.darkPage),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.darkInk, PaperTokens.darkCanvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.darkOnAccent, PaperTokens.darkInk),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.darkDanger, PaperTokens.darkCanvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightOnAccent, PaperTokens.lightReconnecting),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightPage, PaperTokens.welcomeBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.darkMeta, PaperTokens.welcomeBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(PaperTokens.lightOnAccent, PaperTokens.lightInk),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('library controls have semantics labels', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const LibraryScreen(), libraryModel());
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    expect(find.bySemanticsLabel('Saving · 76% battery'), findsOneWidget);
    expect(find.bySemanticsLabel('New notebook'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Lecture notes')), findsWidgets);
    expect(find.text('Lecture notes'), findsOneWidget);
    handle.dispose();
  });

  for (final name in ['library', 'notebook', 'editor', 'pen', 'sync issue']) {
    testWidgets('layout holds at 200% text scale on $name', (tester) async {
      final model = libraryModel();
      final home = switch (name) {
        'notebook' => NotebookPagesScreen(notebookId: model.notebooks.first.id),
        'editor' => PageEditorScreen(
          notebookId: model.notebooks.first.id,
          pageId: 'page-lecture-3',
        ),
        'pen' => const DeviceScreen(),
        'sync issue' => const SyncIssueScreen(),
        _ => const LibraryScreen(),
      };
      await _pump(tester, home, model, textScale: 2, syncFailed: true);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  AppModel model, {
  double textScale = 1,
  bool syncFailed = false,
}) async {
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
          SimulatedPenTransport(manual: true),
        ),
        appControllerProvider.overrideWith(() => AppController(model)),
        if (syncFailed)
          syncStatusProvider.overrideWith((ref) => const SyncFailed(Offline())),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contrast(Color foreground, Color background) {
  final lighter = math.max(_luminance(foreground), _luminance(background));
  final darker = math.min(_luminance(foreground), _luminance(background));
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
