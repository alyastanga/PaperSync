import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool _isEmailAddress(String value) => _email.hasMatch(value.trim());

/// Email code sign-in. A resend is allowed 60 seconds after the last send.
Future<void> showSignInSheet(
  BuildContext context, {
  required Future<void> Function(String email) sendCode,
  required Future<void> Function(String email, String code) verifyCode,
  String initialEmail = '',
}) {
  final colors = Theme.of(context).extension<AppColors>()!;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PaperTokens.radiusCard),
      ),
    ),
    builder: (context) {
      return _SignInSheet(
        sendCode: sendCode,
        verifyCode: verifyCode,
        initialEmail: initialEmail,
      );
    },
  );
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({
    required this.sendCode,
    required this.verifyCode,
    this.initialEmail = '',
  });

  final Future<void> Function(String email) sendCode;
  final Future<void> Function(String email, String code) verifyCode;
  final String initialEmail;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final TextEditingController _code = TextEditingController();
  Timer? _resend;
  var _secondsLeft = 0;
  var _codeSent = false;
  var _busy = false;
  var _message = '';

  @override
  void dispose() {
    _resend?.cancel();
    _emailController.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        PaperTokens.space24,
        PaperTokens.space16,
        PaperTokens.space24,
        PaperTokens.space16 + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Back up notebooks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: PaperTokens.space8),
          Text(
            'We email a 6-digit code. Notes stay on this phone either way.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: PaperTokens.space16),
          _Field(
            label: 'Email',
            hint: 'name@example.com',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_codeSent,
            onChanged: (_) => setState(() {}),
          ),
          if (_codeSent) ...[
            const SizedBox(height: PaperTokens.space12),
            _Field(
              label: 'Code',
              hint: '6-digit code',
              controller: _code,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (_message.isNotEmpty) ...[
            const SizedBox(height: PaperTokens.space8),
            Text(
              _message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.danger),
            ),
          ],
          const SizedBox(height: PaperTokens.space16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_codeSent ? 'Verify' : 'Send code'),
          ),
          if (_codeSent)
            TextButton(
              onPressed: _secondsLeft > 0 || _busy ? null : _send,
              child: Text(
                _secondsLeft > 0 ? 'Resend in ${_secondsLeft}s' : 'Resend code',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_codeSent) {
      await _verify();
      return;
    }
    await _send();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (!_isEmailAddress(email)) {
      setState(() => _message = 'Enter an email address.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await widget.sendCode(email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _secondsLeft = 60;
      });
      _resend?.cancel();
      _resend = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _secondsLeft -= 1;
          if (_secondsLeft <= 0) timer.cancel();
        });
      });
    } on Object {
      if (!mounted) return;
      setState(() => _message = "Couldn't send the code.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _message = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await widget.verifyCode(_emailController.text.trim(), code);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _message = "That code didn't work.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.keyboardType,
    this.enabled = true,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: PaperTokens.space8),
        Semantics(
          label: label,
          textField: true,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            autocorrect: false,
            enabled: enabled,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.meta),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
