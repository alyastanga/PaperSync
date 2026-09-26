import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cloud.dart';
import '../state/ui_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';

/// Account frame `2003:192`.
///
/// Storage size and "last sync" time are not recorded. The mobile-data row
/// is a local switch and does not change sync.
class AccountSyncScreen extends ConsumerWidget {
  const AccountSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(uiPreferencesProvider);
    final controller = ref.read(uiPreferencesProvider.notifier);
    final status = ref.watch(syncStatusProvider);
    final name = prefs.displayName.trim().isEmpty
        ? 'Not signed in'
        : prefs.displayName.trim();
    final email = prefs.email.trim().isEmpty
        ? 'Email not on this phone'
        : prefs.email.trim();
    final lastSync = lastSyncLine(status);

    return Scaffold(
      appBar: AppTopBar(
        height: PaperTokens.formBarHeight,
        leading: BarAction(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const TopTitle('Account and sync'),
      ),
      body: Column(
        children: [
          const SizedBox(height: PaperTokens.space12),
          Container(
            width: PaperTokens.avatarSize,
            height: PaperTokens.avatarSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.line,
              shape: BoxShape.circle,
            ),
            child: Text(prefs.initial, style: PaperType.avatar(colors.ink)),
          ),
          const SizedBox(height: PaperTokens.space8),
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: PaperTokens.space8),
          Text(email, style: PaperType.caption(colors.meta)),
          const SizedBox(height: PaperTokens.space8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: PaperTokens.space24,
              ),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.page,
                    borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
                    border: Border.all(color: colors.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(PaperTokens.space16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: PaperTokens.statusDotLive,
                              height: PaperTokens.statusDotLive,
                              decoration: BoxDecoration(
                                color: syncDidFail(status)
                                    ? colors.danger
                                    : colors.statusSaving,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: PaperTokens.space8),
                            Text(
                              syncRowLabel(status),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: PaperTokens.space8),
                        Text(
                          lastSync,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                SettingsTile(
                  title: 'Sync over mobile data',
                  trailing: Text(
                    prefs.mobileDataLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  onPressed: controller.toggleMobileData,
                ),
                SettingsTile(
                  title: 'Storage used',
                  trailing: Text(
                    'On this phone',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                PaperTokens.space16,
                0,
                PaperTokens.space16,
                PaperTokens.space24,
              ),
              child: TextButton(
                onPressed: () {
                  unawaited(ref.read(paperSyncAuthProvider).signOut());
                  controller.clearProfile();
                },
                style: TextButton.styleFrom(foregroundColor: colors.danger),
                child: const Text('Sign out'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
