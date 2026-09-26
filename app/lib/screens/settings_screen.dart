import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../state/cloud.dart';
import '../state/ui_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import 'account_sync_screen.dart';
import 'comic_strip_screen.dart';
import 'device_screen.dart';
import 'sync_issue_screen.dart';

/// Settings frame `2003:190`. Recognition, mobile data, and export are local.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(uiPreferencesProvider);
    final prefsController = ref.read(uiPreferencesProvider.notifier);
    final link = ref.watch(appControllerProvider).link;
    final status = ref.watch(syncStatusProvider);
    final name = prefs.displayName.trim().isEmpty
        ? 'Not signed in'
        : prefs.displayName.trim();
    final email = prefs.email.trim().isEmpty
        ? 'Email not on this phone'
        : prefs.email.trim();
    final battery = link.batteryPercent;
    final penLine = link.penName == null
        ? 'No pen paired'
        : battery == null
        ? link.penName!
        : '${link.penName} · $battery%';

    return Scaffold(
      appBar: AppTopBar(
        height: PaperTokens.formBarHeight,
        leading: BarAction(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const TopTitle('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PaperTokens.space24,
          0,
          PaperTokens.space24,
          PaperTokens.space28,
        ),
        children: [
          const SectionLabel('ACCOUNT'),
          SettingsTile(
            title: name,
            subtitle: email,
            trailing: Text(
              'View',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountSyncScreen(),
                ),
              );
            },
          ),
          Divider(height: 1, color: colors.line),
          const SectionLabel('PAPERSYNC'),
          SettingsTile(
            title: 'Pen and connection',
            subtitle: penLine,
            trailing: Text(
              'Open',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DeviceScreen()),
              );
            },
          ),
          SettingsTile(
            title: 'Sync',
            subtitle: syncRowLabel(status),
            trailing: Container(
              width: PaperTokens.statusDotLive,
              height: PaperTokens.statusDotLive,
              decoration: BoxDecoration(
                color: syncDidFail(status)
                    ? colors.danger
                    : colors.statusSaving,
                shape: BoxShape.circle,
              ),
            ),
            onPressed: () {
              final next = syncDidFail(status)
                  ? const SyncIssueScreen()
                  : const AccountSyncScreen();
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => next));
            },
          ),
          SettingsTile(
            title: 'Handwriting recognition',
            trailing: Text(
              prefs.handwritingLabel,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: prefsController.toggleHandwriting,
          ),
          Divider(height: 1, color: colors.line),
          SettingsTile(
            title: 'Appearance',
            trailing: Text(
              prefs.appearanceLabel,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: prefsController.cycleAppearance,
          ),
          SettingsTile(
            title: 'Export defaults',
            trailing: Text(
              prefs.exportLabel,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: prefsController.cycleExport,
          ),
          const SizedBox(height: PaperTokens.space16),
          SettingsTile(
            title: 'Comic strip',
            subtitle: 'Page 1 in the design file',
            trailing: Text(
              'Open',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ComicStripScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
