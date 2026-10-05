import 'package:flutter/material.dart';

import 'palette.dart';

/// Two faces, with a strict division of labour: Space Grotesk carries voice,
/// JetBrains Mono carries anything the user might need to verify character
/// by character — addresses, amounts, signatures.
///
/// Both are bundled as assets rather than fetched at runtime. Downloading
/// type on first launch means a user on a bad connection sees fallback faces
/// at exactly the moment the app is making its first impression.
abstract final class AppType {
  static const display = 'Space Grotesk';
  static const code = 'JetBrains Mono';

  static TextTheme build() {
    return const TextTheme(
      displaySmall: TextStyle(
        fontFamily: display,
        fontSize: 34,
        height: 1.1,
        letterSpacing: -1,
        fontWeight: FontWeight.w700,
        color: Palette.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontFamily: display,
        fontSize: 26,
        height: 1.15,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w700,
        color: Palette.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: display,
        fontSize: 19,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w600,
        color: Palette.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: display,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Palette.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: display,
        fontSize: 15,
        height: 1.45,
        color: Palette.textSecondary,
      ),
      bodyMedium: TextStyle(
        fontFamily: display,
        fontSize: 13.5,
        height: 1.45,
        color: Palette.textSecondary,
      ),
      labelLarge: TextStyle(
        fontFamily: display,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: Palette.textPrimary,
      ),
      // Section eyebrows: small, wide, quiet.
      labelSmall: TextStyle(
        fontFamily: display,
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w600,
        color: Palette.textMuted,
      ),
    );
  }

  /// Wallet addresses, signatures, hashes.
  static TextStyle mono({
    double size = 13,
    Color color = Palette.textSecondary,
    FontWeight weight = FontWeight.w500,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: code,
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: spacing,
  );

  /// Amounts. Tabular figures so digits do not jitter as values animate.
  static TextStyle amount({
    double size = 40,
    Color color = Palette.textPrimary,
  }) => TextStyle(
    fontFamily: code,
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
