import 'package:flutter/material.dart';

/// Design tokens derived from the PaperSync Figma file
/// (`9Q4PKHBzk3oVIigtd75nLo`, node `2003:129`).
///
/// Light colors, type, spacing, and radii come from that node's fills, text
/// styles, and auto-layout. The file has no dark frames and the styles
/// endpoint is outside the `file_content:read` scope, so the dark palette is
/// the inverse already used with these light colors.
///
/// [lightMeta] is the Figma gray `#8A847C` darkened just enough to clear
/// WCAG AA (4.5:1) on both the page and the canvas. The original value is
/// [lightFigmaMeta] (about 3.3:1 on the canvas).
abstract final class PaperTokens {
  static const fontFamily = 'Inter';

  static const lightPage = Color(0xFFFFFDFC);
  static const lightCanvas = Color(0xFFF4F1EC);
  static const lightInk = Color(0xFF1C1917);
  static const lightLine = Color(0xFFE6E1D8);
  static const lightFigmaMeta = Color(0xFF8A847C);
  static const lightMeta = Color(0xFF726D66);
  static const lightDanger = Color(0xFF8E3B3B);
  static const lightSaving = Color(0xFF3F6B4E);
  static const lightReconnecting = Color(0xFF8A6232);
  static const lightOnAccent = Color(0xFFFFFDFC);

  static const darkPage = Color(0xFF171614);
  static const darkCanvas = Color(0xFF0E0D0C);
  static const darkInk = Color(0xFFF3F0EA);
  static const darkLine = Color(0xFF2C2A26);
  static const darkMeta = Color(0xFFA39E94);
  static const darkDanger = Color(0xFFE7B4B0);
  static const darkSaving = Color(0xFF8FBF9E);
  static const darkReconnecting = Color(0xFFE0B27A);
  static const darkOnAccent = Color(0xFF1C1917);

  /// Stored stroke black. Screen ink follows the theme; export stays this.
  static const storedInk = Color(0xFF1A1A1A);
  static const inkBlue = Color(0xFF2563EB);
  static const inkRed = Color(0xFFDC2626);

  static const space2 = 2.0;
  static const space4 = 4.0;
  static const space6 = 6.0;
  static const space7 = 7.0;
  static const space8 = 8.0;
  static const space10 = 10.0;
  static const space12 = 12.0;
  static const space14 = 14.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space28 = 28.0;
  static const space32 = 32.0;

  static const radiusStroke = 2.0;
  static const radiusGlyph = 4.0;
  static const radiusButton = 8.0;
  static const radiusCluster = 10.0;
  static const radiusCard = 12.0;
  static const radiusPill = 999.0;

  static const elevation = 0.0;
  static const minTap = 48.0;
  static const barHeight = 60.0;
  static const formBarHeight = 56.0;
  static const liveHeaderHeight = 64.0;
  static const avatarSize = 64.0;

  /// Welcome frame `2003:172` paints variable `2003:151` as black. Every other
  /// screen resolves that same variable to [lightCanvas]. The render is black.
  static const welcomeBackground = Color(0xFF000000);
  static const frameWidth = 390.0;
  static const frameHeight = 844.0;

  static const statusDot = 6.0;
  static const statusDotLive = 8.0;
  static const inkDot = 16.0;
  static const pagePreviewWidth = 250.0;
  static const penGlyph = 110.0;
  static const warnBadge = 60.0;

  static const titleSize = 16.0;
  static const titleHeight = 19.363636016845703 / 16;
  static const cardTitleSize = 15.0;
  static const cardTitleHeight = 18.15340805053711 / 15;
  static const bodySize = 15.0;
  static const bodyHeight = 18.15340805053711 / 15;
  static const bodyRelaxedHeight = 22 / 15;
  static const labelSize = 14.0;
  static const labelHeight = 16.94318199157715 / 14;
  static const metaSize = 12.0;
  static const metaHeight = 14.522727012634277 / 12;
  static const toolSize = 11.0;
  static const toolHeight = 13.3125 / 11;
  static const displaySize = 28.0;
  static const displayHeight = 33.8863639831543 / 28;
  static const avatarFontSize = 24.0;
  static const avatarFontHeight = 29.045454025268555 / 24;
  static const captionSize = 13.0;
  static const captionHeight = 15.732954025268555 / 13;
}

/// Type scale from the Figma text styles. Sizes are the file's; weights are
/// 400, 500, and 600. Letter spacing in the file is 0.
abstract final class PaperType {
  static TextStyle display(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.displaySize,
    height: PaperTokens.displayHeight,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle screenTitle(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.titleSize,
    height: PaperTokens.titleHeight,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle cardTitle(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.cardTitleSize,
    height: PaperTokens.cardTitleHeight,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle body(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.bodySize,
    height: PaperTokens.bodyHeight,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle bodyRelaxed(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.bodySize,
    height: PaperTokens.bodyRelaxedHeight,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle label(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.labelSize,
    height: PaperTokens.labelHeight,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle labelStrong(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.labelSize,
    height: PaperTokens.labelHeight,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle meta(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.metaSize,
    height: PaperTokens.metaHeight,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle metaStrong(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.metaSize,
    height: PaperTokens.metaHeight,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle avatar(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.avatarFontSize,
    height: PaperTokens.avatarFontHeight,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle caption(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.captionSize,
    height: PaperTokens.captionHeight,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: color,
  );

  static TextStyle tool(Color color) => TextStyle(
    fontFamily: PaperTokens.fontFamily,
    fontSize: PaperTokens.toolSize,
    height: PaperTokens.toolHeight,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: color,
  );
}
