import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/chrome.dart';
import '../widgets/paper_svg.dart';
import 'create_account_screen.dart';
import 'sign_in_screen.dart';

/// Launch frame `2003:172`. The file paints this one screen black.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaperTokens.welcomeBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperTokens.space24,
            72,
            PaperTokens.space24,
            PaperTokens.space32,
          ),
          child: Column(
            children: [
              const PaperSvg.inkPreview(adapt: false),
              const SizedBox(height: PaperTokens.space16),
              Text(
                'PaperSync',
                textAlign: TextAlign.center,
                style: PaperType.display(PaperTokens.lightPage),
              ),
              const SizedBox(height: PaperTokens.space8),
              Text(
                'Your paper notebook, searchable\nand safely synced.',
                textAlign: TextAlign.center,
                style: PaperType.bodyRelaxed(PaperTokens.darkMeta),
              ),
              const Spacer(),
              _WelcomePrimary(
                label: 'Sign in',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignInScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: PaperTokens.space12),
              SecondaryButton(
                label: 'Create account',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateAccountScreen(),
                    ),
                  );
                },
              ),
              TextButton(
                onPressed: onContinue,
                child: Text(
                  'Continue without account',
                  style: PaperType.caption(PaperTokens.darkMeta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePrimary extends StatelessWidget {
  const _WelcomePrimary({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.onAccent,
          side: BorderSide(color: colors.page),
          minimumSize: const Size(double.infinity, PaperTokens.minTap),
        ),
        child: Text(label),
      ),
    );
  }
}
