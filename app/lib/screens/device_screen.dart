import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format/labels.dart';
import '../models/pen_link.dart';
import '../state/app_controller.dart';
import '../state/cloud.dart';
import '../theme/app_colors.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/dialogs.dart';
import '../widgets/sign_in_sheet.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final link = model.link;
    final colors = context.colors;

    final signedIn = ref.watch(paperSyncAuthProvider).current != null;
    final canBackUp = ref.watch(backupReadyProvider);

    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const TopTitle('Pen'),
        link: link,
      ),
      body: Column(
        children: [
          if (canBackUp)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: signedIn
                    ? TextButton(
                        onPressed: () async {
                          await ref.read(paperSyncAuthProvider).signOut();
                        },
                        child: const Text('Sign out'),
                      )
                    : TextButton(
                        onPressed: () {
                          final auth = ref.read(paperSyncAuthProvider);
                          unawaited(
                            showSignInSheet(
                              context,
                              sendCode: auth.sendEmailCode,
                              verifyCode: (email, code) {
                                return auth.verifyEmailCode(
                                  email: email,
                                  code: code,
                                );
                              },
                            ),
                          );
                        },
                        child: const Text('Back up notebooks'),
                      ),
              ),
            ),
          Expanded(
            child: link.bonded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.page,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: colors.line),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          link.penName ?? 'Pen',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          link.batteryPercent == null
                                              ? 'Battery unknown'
                                              : '${link.batteryPercent}% battery',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            onPressed:
                                                link.state ==
                                                    LinkState.disconnected
                                                ? () => controller.connectPen(
                                                    link.penName ??
                                                        'PaperSync Pen',
                                                  )
                                                : controller.disconnectPen,
                                            child: Text(
                                              link.state ==
                                                      LinkState.disconnected
                                                  ? 'Connect'
                                                  : 'Disconnect',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => setState(
                                    () => _detailsOpen = !_detailsOpen,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Connection details',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        const Spacer(),
                                        Icon(
                                          _detailsOpen
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_detailsOpen) ...[
                                  _DetailRow(
                                    label: 'Signal',
                                    value: link.signal,
                                  ),
                                  _DetailRow(
                                    label: 'Last packet',
                                    value: link.lastPacket == null
                                        ? 'None'
                                        : formatTime(link.lastPacket!),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () async {
                                  final confirmed = await confirmAction(
                                    context,
                                    title: 'Forget this pen?',
                                    message: 'You can pair it again from this screen.',
                                    confirm: 'Forget',
                                  );
                                  if (!confirmed) return;
                                  controller.forgetPen();
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.danger,
                                ),
                                child: const Text('Forget'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : _Pairing(
                    permissionGranted: link.permissionGranted,
                    nearby: model.nearbyPens,
                    onAllow: controller.grantPermission,
                    onPick: (name) {
                      controller.connectPen(name);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Pairing extends StatelessWidget {
  const _Pairing({
    required this.permissionGranted,
    required this.nearby,
    required this.onAllow,
    required this.onPick,
  });

  final bool permissionGranted;
  final List<String> nearby;
  final VoidCallback onAllow;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text(
          'PaperSync connects to the pen that writes on your notebook.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (!permissionGranted)
          FilledButton(onPressed: onAllow, child: const Text('Allow Bluetooth'))
        else
          for (final name in nearby)
            InkWell(
              onTap: () => onPick(name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
        if (permissionGranted && nearby.isEmpty)
          Text(
            'No pens nearby.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.meta),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
  }
}
