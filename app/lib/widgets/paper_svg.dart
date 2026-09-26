import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Illustrations exported from the Figma frames.
class PaperSvg extends StatelessWidget {
  const PaperSvg.inkPreview({super.key, bool adapt = true})
    : _asset = 'assets/images/ink-preview.svg',
      _size = const Size(250, 158),
      _label = 'PaperSync ink preview',
      _mapChrome = adapt;

  const PaperSvg.pen({super.key})
    : _asset = 'assets/images/pen-glyph.svg',
      _size = const Size(PaperTokens.penGlyph, PaperTokens.penGlyph),
      _label = 'PaperSync pen',
      _mapChrome = true;

  const PaperSvg.warn({super.key})
    : _asset = 'assets/images/sync-warn.svg',
      _size = const Size(PaperTokens.warnBadge, PaperTokens.warnBadge),
      _label = 'Sync problem',
      _mapChrome = false;

  final String _asset;
  final Size _size;
  final String _label;
  final bool _mapChrome;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SvgPicture.asset(
      _asset,
      width: _size.width,
      height: _size.height,
      semanticsLabel: _label,
      colorMapper: _mapChrome ? _ChromeMapper(colors) : null,
    );
  }
}

class _ChromeMapper extends ColorMapper {
  const _ChromeMapper(this.colors);

  final AppColors colors;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return switch (rgb) {
      0xFFFDFC => colors.page,
      0x1C1917 => colors.ink,
      0xE6E1D8 => colors.line,
      _ => color,
    };
  }
}
