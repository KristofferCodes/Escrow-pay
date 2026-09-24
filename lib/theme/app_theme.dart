import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';
import 'typography.dart';

abstract final class AppTheme {
  /// Escrow Pay is dark-only by design: the glass surfaces and the accent
  /// gradient are built for a near-black ground and do not have a light
  /// counterpart worth shipping for a demo.
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Palette.violet,
      secondary: Palette.cyan,
      surface: Palette.surface,
      error: Palette.danger,
      onPrimary: Colors.white,
      onSurface: Palette.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Palette.void_,
      textTheme: AppType.build(),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: _fieldBorder(Palette.hairline),
        enabledBorder: _fieldBorder(Palette.hairline),
        focusedBorder: _fieldBorder(Palette.violet, width: 1.4),
        errorBorder: _fieldBorder(Palette.danger),
        focusedErrorBorder: _fieldBorder(Palette.danger, width: 1.4),
        labelStyle: const TextStyle(color: Palette.textMuted),
        floatingLabelStyle: const TextStyle(color: Palette.cyan),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Palette.surfaceRaised,
        contentTextStyle: const TextStyle(color: Palette.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(
        color: Palette.hairline,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Shared geometry so panels, buttons and sheets round consistently.
abstract final class Radii {
  static const panel = BorderRadius.all(Radius.circular(22));
  static const control = BorderRadius.all(Radius.circular(16));
  static const chip = BorderRadius.all(Radius.circular(999));
}

/// A 4pt spacing ramp.
abstract final class Gap {
  static const xs = SizedBox(height: 4, width: 4);
  static const sm = SizedBox(height: 8, width: 8);
  static const md = SizedBox(height: 16, width: 16);
  static const lg = SizedBox(height: 24, width: 24);
  static const xl = SizedBox(height: 36, width: 36);
}
