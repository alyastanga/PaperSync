import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cloud.dart';
import '../state/ui_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/sign_in_sheet.dart';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Name, email, and password form from frame `2003:176`.
///
/// There is no password account API. A name typed here stays on this phone.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  var _nameError = '';
  var _emailError = '';
  var _passwordError = '';
  var _message = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
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
        title: const TopTitle('Create account'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                PaperTokens.space24,
                PaperTokens.space12,
                PaperTokens.space24,
                PaperTokens.space16,
              ),
              children: [
                PaperField(
                  label: 'Name',
                  hint: 'Your name',
                  controller: _name,
                  error: _nameError.isEmpty ? null : _nameError,
                  onChanged: (_) => setState(() => _nameError = ''),
                ),
                const SizedBox(height: PaperTokens.space16),
                PaperField(
                  label: 'Email',
                  hint: 'name@example.com',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  error: _emailError.isEmpty ? null : _emailError,
                  onChanged: (_) => setState(() => _emailError = ''),
                ),
                const SizedBox(height: PaperTokens.space16),
                PaperField(
                  label: 'Password',
                  hint: 'Create a password',
                  controller: _password,
                  obscure: true,
                  error: _passwordError.isEmpty ? null : _passwordError,
                  onChanged: (_) => setState(() => _passwordError = ''),
                ),
                const SizedBox(height: PaperTokens.space8),
                Text(
                  'At least 8 characters',
                  style: PaperType.caption(colors.meta),
                ),
                const SizedBox(height: PaperTokens.space16),
                PrimaryButton(
                  label: 'Create account',
                  expand: true,
                  onPressed: () => unawaited(_submit()),
                ),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: PaperTokens.space12),
                  Text(
                    _message,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.meta),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperTokens.space28,
              0,
              PaperTokens.space28,
              PaperTokens.space28,
            ),
            child: Text(
              'By continuing, you agree to the Terms\nand Privacy Policy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final nameError = name.isEmpty ? 'Enter your name.' : '';
    final emailError = _emailPattern.hasMatch(email)
        ? ''
        : 'Enter an email address.';
    final passwordError = _password.text.length < 8
        ? 'Use at least 8 characters.'
        : '';
    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _message = '';
    });
    if (nameError.isNotEmpty ||
        emailError.isNotEmpty ||
        passwordError.isNotEmpty) {
      return;
    }
    ref
        .read(uiPreferencesProvider.notifier)
        .rememberProfile(name: name, email: email);
    if (!ref.read(backupReadyProvider)) {
      setState(() {
        _message =
            'Your name stays on this phone. Backup isn\'t configured, '
            'so this does not create a cloud account. The password is not saved.';
      });
      return;
    }
    final auth = ref.read(paperSyncAuthProvider);
    setState(() {
      _message = "We'll email a code to finish. The password is not saved.";
    });
    await showSignInSheet(
      context,
      initialEmail: email,
      sendCode: auth.sendEmailCode,
      verifyCode: (address, code) {
        return auth.verifyEmailCode(email: address, code: code);
      },
    );
    if (!mounted) return;
    if (ref.read(paperSyncAuthProvider).current != null) {
      ref.read(uiPreferencesProvider.notifier).enterLibrary();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
