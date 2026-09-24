import 'package:flutter/material.dart';

/// Colour tokens for Escrow Pay.
///
/// The surface ramp is deliberately near-black rather than pure black: glass
/// panels need something to sit against, and `#000` flattens the blur.
abstract final class Palette {
  // Surfaces, darkest first.
  static const void_ = Color(0xFF07070C);
  static const surface = Color(0xFF0C0C14);
  static const surfaceRaised = Color(0xFF13131F);
  static const hairline = Color(0x1AFFFFFF);
  static const hairlineStrong = Color(0x33FFFFFF);

  // Accent ramp. Purple to cyan, used sparingly.
  static const violet = Color(0xFF8B5CF6);
  static const indigo = Color(0xFF6366F1);
  static const cyan = Color(0xFF22D3EE);

  // Semantic.
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFFB7185);

  // Text.
  static const textPrimary = Color(0xFFF4F4F8);
  static const textSecondary = Color(0xFFA1A1B5);
  static const textMuted = Color(0xFF6B6B80);

  /// The primary accent. Used on CTAs, active states, and the status ring.
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, indigo, cyan],
  );

  /// A dimmed accent for backgrounds that must not compete with content.
  static const accentSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x338B5CF6), Color(0x3322D3EE)],
  );

  /// Glass fill for panels sitting over the circuit backdrop.
  static const glass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
  );

  /// The accent colour a given escrow state should read as.
  static Color forState(String state) => switch (state) {
    'created' => violet,
    'funded' => cyan,
    'released' => success,
    'refunded' => warning,
    _ => textMuted,
  };
}
