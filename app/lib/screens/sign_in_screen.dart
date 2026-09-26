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
import 'create_account_screen.dart';
import 'reset_password_screen.dart';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Password form from frame `2003:174`.
///
/// Phase 4 signs in with an email code. The password is not sent anywhere.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  var _obscure = true;
  var _emailError = '';
  var _passwordError = '';
  var _message = '';

  @override
  void dispose() {
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
        title: const TopTitle('Sign in'),
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
                  hint: 'Enter password',
                  controller: _password,
                  obscure: _obscure,
                  error: _passwordError.isEmpty ? null : _passwordError,
                  onChanged: (_) => setState(() => _passwordError = ''),
                  suffix: TextButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    child: Text(_obscure ? 'Show' : 'Hide'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ResetPasswordScreen(),
                        ),
                      );
                    },
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: PaperTokens.space8),
                PrimaryButton(
                  label: 'Sign in',
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
            padding: const EdgeInsets.only(bottom: PaperTokens.space8),
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CreateAccountScreen(),
                  ),
                );
              },
              child: Text(
                'New to PaperSync? Create account',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final emailError = _emailPattern.hasMatch(email)
        ? ''
        : 'Enter an email address.';
    final passwordError = _password.text.isEmpty ? 'Enter a password.' : '';
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _message = '';
    });
    if (emailError.isNotEmpty || passwordError.isNotEmpty) return;
    if (!ref.read(backupReadyProvider)) {
      setState(() {
        _message =
            "Backup isn't configured, so this screen can't sign you in. "
            'The password is not sent.';
      });
      return;
    }
    final auth = ref.read(paperSyncAuthProvider);
    setState(() {
      _message = "We'll email a code. The password is not sent.";
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
