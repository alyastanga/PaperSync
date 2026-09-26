import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../state/cloud.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/paper_svg.dart';

/// Sync recovery frame `2003:196`.
///
/// The page list is the notebooks on this phone. Sync status does not name
/// which pages failed, so the screen does not invent a waiting set.
class SyncIssueScreen extends ConsumerWidget {
  const SyncIssueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final model = ref.watch(appControllerProvider);
    final notebooks = model.notebooks;
    final pageCount = notebooks.fold<int>(
      0,
      (count, notebook) => count + notebook.pages.length,
    );
    final title = pageCount == 0
        ? "Couldn't back up"
        : pageCount == 1
        ? '1 page is still on this phone'
        : '$pageCount pages are still on this phone';
    final first = notebooks.isEmpty ? null : notebooks.first;
    final indexes = first == null
        ? const <int>[]
        : (first.pages.map((page) => page.pageIndex).toList()..sort());

    return Scaffold(
      appBar: AppTopBar(
        height: PaperTokens.formBarHeight,
        leading: BarAction(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const TopTitle('Sync issue'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PaperTokens.space24,
          PaperTokens.space20,
          PaperTokens.space24,
          PaperTokens.space28,
        ),
        children: [
          const Center(child: PaperSvg.warn()),
          const SizedBox(height: PaperTokens.space16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: PaperTokens.space8),
          Text(
            'Your pages are safe on this device.\nReconnect and try again when ready.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.meta),
          ),
          const SizedBox(height: PaperTokens.space16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.page,
              borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
              border: Border.all(color: colors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(PaperTokens.space14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          first?.name ?? 'Library',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        'Waiting',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: PaperTokens.space6),
                  Text(
                    _pageLine(indexes),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: PaperTokens.space16),
          PrimaryButton(
            label: 'Retry',
            expand: true,
            onPressed: () {
              unawaited(ref.read(syncCoordinatorProvider).syncNow());
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Continue offline',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.meta),
            ),
          ),
        ],
      ),
    );
  }
}

String _pageLine(List<int> indexes) {
  if (indexes.isEmpty) return 'No pages yet';
  if (indexes.length == 1) return 'Page ${indexes.first}';
  if (indexes.length == 2) {
    return 'Pages ${indexes[0]} and ${indexes[1]}';
  }
  final head = indexes.take(indexes.length - 1).join(', ');
  return 'Pages $head, and ${indexes.last}';
}
