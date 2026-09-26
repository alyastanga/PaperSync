import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../state/cloud.dart';
import '../state/notebook_store_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/dialogs.dart';
import '../widgets/notebook_card.dart';
import 'device_screen.dart';
import 'notebook_pages_screen.dart';
import 'search_screen.dart';

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
        leading: IconButton(
          tooltip: 'Search',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            );
          },
          icon: const Icon(Icons.search),
        ),
        title: const TopTitle('Library'),
        link: model.link,
        onStatusTap: () => _openDevice(context),
      ),
      body: Column(
        children: [
          if (notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                notice,
                key: const Key('storage-notice'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.colors.danger),
              ),
            ),
          if (backup != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                backup,
                key: const Key('backup-notice'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.colors.danger),
              ),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: TextButton(
                            onPressed: () =>
                                _createNotebook(context, controller),
                            child: const Text('New notebook'),
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
                            const spacing = 28.0;
                            const padding = 24.0;
                            final width =
                                (constraints.maxWidth -
                                    padding * 2 -
                                    spacing * (count - 1)) /
                                count;
                            final thumbHeight = width / pageAspect;
                            final cellHeight = thumbHeight + 58;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: count,
                                    mainAxisSpacing: 28,
                                    crossAxisSpacing: spacing,
                                    childAspectRatio: width / cellHeight,
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              bonded
                  ? 'Notebooks you write show up here.'
                  : 'Pair your pen to start a notebook.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.meta),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onPrimary,
              child: Text(bonded ? 'New notebook' : 'Pair your pen'),
            ),
          ],
        ),
      ),
    );
  }
}
