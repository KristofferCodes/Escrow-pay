import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

/// Two faces, with a strict division of labour: Space Grotesk carries voice,
/// JetBrains Mono carries anything the user might need to verify character by
/// character — addresses, amounts, signatures.
abstract final class AppType {
  static TextTheme build() {
    final display = GoogleFonts.spaceGroteskTextTheme();

    return TextTheme(
      displaySmall: display.displaySmall?.copyWith(
        fontSize: 34,
        height: 1.1,
        letterSpacing: -1.0,
        fontWeight: FontWeight.w700,
        color: Palette.textPrimary,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontSize: 26,
        height: 1.15,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w700,
        color: Palette.textPrimary,
      ),
      titleLarge: display.titleLarge?.copyWith(
        fontSize: 19,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w600,
        color: Palette.textPrimary,
      ),
      titleMedium: display.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Palette.textPrimary,
      ),
      bodyLarge: display.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.45,
        color: Palette.textSecondary,
      ),
      bodyMedium: display.bodyMedium?.copyWith(
        fontSize: 13.5,
        height: 1.45,
        color: Palette.textSecondary,
      ),
      labelLarge: display.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: Palette.textPrimary,
      ),
      // Section eyebrows: small, wide, quiet.
      labelSmall: display.labelSmall?.copyWith(
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
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: spacing,
  );

  /// Amounts. Tabular figures so digits do not jitter as values animate.
  static TextStyle amount({
    double size = 40,
    Color color = Palette.textPrimary,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.0,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
