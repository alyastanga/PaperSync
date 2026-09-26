import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Text control in a bar. The hit target is at least 48 dp.
class BarAction extends StatelessWidget {
  const BarAction({
    super.key,
    required this.label,
    required this.onPressed,
    String? tooltip,
  }) : tooltip = tooltip ?? label;

  final String label;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: colors.meta,
          textStyle: Theme.of(context).textTheme.labelMedium,
          minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
          padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// The "More" menu on notebook and page bars.
class BarMenu extends StatelessWidget {
  const BarMenu({
    super.key,
    required this.tooltip,
    required this.onSelected,
    required this.itemBuilder,
  });

  final String tooltip;
  final void Function(String value) onSelected;
  final List<PopupMenuEntry<String>> Function(BuildContext context) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: PaperTokens.minTap,
          minHeight: PaperTokens.minTap,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space8),
          child: Center(
            child: Text(
              'More',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.meta),
            ),
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(
          expand ? double.infinity : PaperTokens.minTap,
          PaperTokens.minTap,
        ),
      ),
      child: Text(label),
    );
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          backgroundColor: colors.page,
          textStyle: PaperType.cardTitle(colors.ink),
          minimumSize: const Size(double.infinity, PaperTokens.minTap),
          side: BorderSide(color: colors.ink, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      ),
    );
  }
}

class PaperField extends StatelessWidget {
  const PaperField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.suffix,
    this.error,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  final String? error;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: PaperTokens.space8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          onChanged: onChanged,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            errorStyle: PaperType.caption(colors.danger),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: PaperTokens.minTap,
              minHeight: PaperTokens.minTap,
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.onPressed,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: PaperTokens.minTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: PaperTokens.space14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: PaperTokens.space4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: PaperTokens.space12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: PaperTokens.space12,
        bottom: PaperTokens.space4,
      ),
      child: Text(text, style: PaperType.metaStrong(context.colors.meta)),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.onTap,
    this.messageKey,
  });

  final String message;
  final VoidCallback? onTap;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: PaperTokens.minTap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.page,
          borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
          border: Border.all(color: colors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PaperTokens.space16,
            vertical: PaperTokens.space12,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              message,
              key: messageKey,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.danger),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PaperTokens.space24,
        PaperTokens.space12,
        PaperTokens.space24,
        0,
      ),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
              child: body,
            ),
    );
  }
}
