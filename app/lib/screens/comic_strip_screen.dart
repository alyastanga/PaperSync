import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';

/// Page 1 frame `5:360`, "Comic Strip".
///
/// The images API returned no render for this node. The screen shows the
/// text that is actually in the frame. It is not part of the notebook flow.
class ComicStripScreen extends StatelessWidget {
  const ComicStripScreen({super.key});

  static const captions = <String>[
    'AFTER YEARS OF AUTHORITARIAN RULE UNDER PRESIDING PRESIDENT FERDINAND MARCOS, THE FILIPINO PEOPLE UP IN THE PEACEFUL PEOPLE POWER REVOLUTION OF 1986!',
    'THE HISTORIC EVENT LED TO OUSTED MARCOS AND THE INSTALLATION OF CORAZON C. AQUINO AS  NEW PRESIDENT',
    'PRESIDENT AQUINO SWIFTLY ESTABLISHES CONSTITUTIONAL COMMISSION IN MAY 1986, COMPOSED OF 50 DIVERSE MEMBERS TO DRAFT A NEW FUNDAMENTAL LAW.',
    'KEY FEATURES: A PRESIDENT DEMOCRACY, A STRONG BILL OF RIGHTS , AND CLEAR CHECK AND BALANCES.',
    'THE PREVIOUS 1973 CONSTITUTION, ENACTED UNDER MARTIAL LAW WAS LARGELY SERVE AS A TOOL FOR AUTHORITARIANISM.\nA NEW SOCIAL CONTRACT WAS DESPERATELY NEEDED',
  ];

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
        title: const TopTitle('1987 Constitution'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PaperTokens.space24,
          PaperTokens.space16,
          PaperTokens.space24,
          PaperTokens.space32,
        ),
        children: [
          Text(
            'PETER M. DELA CRUZ\nCS21S2',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: PaperTokens.space16),
          for (final caption in captions) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.page,
                borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
                border: Border.all(color: colors.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(PaperTokens.space16),
                child: Text(
                  caption,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: PaperTokens.space12),
          ],
        ],
      ),
    );
  }
}
