import 'dart:async';

import 'package:flutter/material.dart';

import '../sync/auth.dart';
import '../theme/app_colors.dart';

/// Email code sign-in. A resend is allowed 60 seconds after the last send.
Future<void> showSignInSheet(
  BuildContext context, {
  required Future<void> Function(String email) sendCode,
  required Future<void> Function(String email, String code) verifyCode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return _SignInSheet(sendCode: sendCode, verifyCode: verifyCode);
    },
  );
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.sendCode, required this.verifyCode});

  final Future<void> Function(String email) sendCode;
  final Future<void> Function(String email, String code) verifyCode;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  Timer? _resend;
  var _secondsLeft = 0;
  var _codeSent = false;
  var _busy = false;
  var _message = '';

  @override
  void dispose() {
    _resend?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Back up notebooks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'We email a 6-digit code. Notes stay on this phone either way.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !_codeSent,
            decoration: InputDecoration(
              hintText: 'Email',
              hintStyle: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.meta),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '6-digit code'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.danger),
            ),
          ],
          const SizedBox(height: 16),
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
    final email = _email.text.trim();
    if (!isEmailAddress(email)) {
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
      await widget.verifyCode(_email.text.trim(), code);
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
