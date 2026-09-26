import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Reset form from frame `2003:178`.
///
/// The artboard includes the "check your inbox" note. There is no reset-link
/// service, so the button does not send mail.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _email = TextEditingController();
  var _error = '';
  var _note = '';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppTopBar(
        height: PaperTokens.formBarHeight,
        leading: BarAction(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const TopTitle('Reset password'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PaperTokens.space24,
          PaperTokens.space12,
          PaperTokens.space24,
          PaperTokens.space28,
        ),
        children: [
          Text(
            'Enter the email for your account.\nWe will send a secure reset link.',
            style: PaperType.bodyRelaxed(colors.ink),
          ),
          const SizedBox(height: PaperTokens.space16),
          PaperField(
            label: 'Email',
            hint: 'name@example.com',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            error: _error.isEmpty ? null : _error,
            onChanged: (_) => setState(() => _error = ''),
          ),
          const SizedBox(height: PaperTokens.space16),
          PrimaryButton(
            label: 'Send reset link',
            expand: true,
            onPressed: _submit,
          ),
          if (_note.isNotEmpty) ...[
            const SizedBox(height: PaperTokens.space12),
            Text(
              _note,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.meta),
            ),
          ],
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
                      Container(
                        width: PaperTokens.statusDotLive,
                        height: PaperTokens.statusDotLive,
                        decoration: BoxDecoration(
                          color: colors.statusSaving,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: PaperTokens.space8),
                      Text(
                        'Check your inbox',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: PaperTokens.space8),
                  Text(
                    'The link expires after 30 minutes.',
                    style: PaperType.caption(colors.meta),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() {
        _error = 'Enter an email address.';
        _note = '';
      });
      return;
    }
    setState(() {
      _error = '';
      _note =
          'Nothing was sent. This build has no reset-link service. '
          'Sign-in uses an email code.';
    });
  }
}
