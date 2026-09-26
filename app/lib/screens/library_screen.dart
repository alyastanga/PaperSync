import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../state/cloud.dart';
import '../state/notebook_store_provider.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/notebook_card.dart';
import '../widgets/paper_svg.dart';
import 'device_screen.dart';
import 'notebook_pages_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_issue_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final notice = ref.watch(storageNoticeProvider);
    final backup = ref.watch(backupNoticeProvider);

    return Scaffold(
      appBar: AppTopBar(
        leading: BarAction(
          label: 'Search',
          tooltip: 'Search',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            );
          },
        ),
        title: const TopTitle('Library'),
        link: model.link,
        onStatusTap: () => _openDevice(context),
      ),
      body: Column(
        children: [
          if (notice != null)
            NoticeBanner(
              message: notice,
              messageKey: const Key('storage-notice'),
            ),
          if (backup != null)
            NoticeBanner(
              message: backup,
              messageKey: const Key('backup-notice'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SyncIssueScreen(),
                  ),
                );
              },
            ),
          Expanded(
            child: model.notebooks.isEmpty
                ? _EmptyLibrary(
                    bonded: model.link.bonded,
                    onPrimary: () {
                      if (model.link.bonded) {
                        unawaited(_createNotebook(context, controller));
                      } else {
                        _openDevice(context);
                      }
                    },
                  )
                : Column(
                    children: [
                      const SizedBox(height: PaperTokens.space12),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PaperTokens.space16,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => _openSettings(context),
                                child: const Text('Settings'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _createNotebook(context, controller),
                                child: const Text('New notebook'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final count = constraints.maxWidth >= 1000
                                ? 4
                                : constraints.maxWidth >= 700
                                ? 3
                                : 2;
                            const spacing = PaperTokens.space16;
                            final width =
                                (constraints.maxWidth -
                                    PaperTokens.space24 * 2 -
                                    spacing * (count - 1)) /
                                count;
                            final scaler = MediaQuery.textScalerOf(context);
                            final textBlock =
                                PaperTokens.space10 +
                                scaler.scale(22) +
                                PaperTokens.space10 +
                                scaler.scale(18);
                            final extent = width / pageAspect + textBlock;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                PaperTokens.space24,
                                PaperTokens.space4,
                                PaperTokens.space24,
                                PaperTokens.space32,
                              ),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: count,
                                    mainAxisSpacing: PaperTokens.space24,
                                    crossAxisSpacing: spacing,
                                    mainAxisExtent: extent,
                                  ),
                              itemCount: model.notebooks.length,
                              itemBuilder: (context, index) {
                                final notebook = model.notebooks[index];
                                return NotebookCard(
                                  notebook: notebook,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => NotebookPagesScreen(
                                          notebookId: notebook.id,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _openDevice(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DeviceScreen()));
  }

  Future<void> _createNotebook(
    BuildContext context,
    AppController controller,
  ) async {
    final name = await askName(context, title: 'New notebook');
    if (name == null || !context.mounted) return;
    final id = controller.createNotebook(name);
    if (id.isEmpty || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotebookPagesScreen(notebookId: id),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.bonded, required this.onPrimary});

  final bool bonded;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PaperTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PaperSvg.inkPreview(),
            const SizedBox(height: PaperTokens.space24),
            Text(
              bonded
                  ? 'Notebooks you write show up here.'
                  : 'Pair your pen to start a notebook.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.meta),
            ),
            const SizedBox(height: PaperTokens.space16),
            PrimaryButton(
              label: bonded ? 'New notebook' : 'Pair your pen',
              onPressed: onPrimary,
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
