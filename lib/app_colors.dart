import 'package:flutter/material.dart';

/// Centralized color palette for the app.
///
/// Defines brand, accent, neutral, and status colors used throughout the UI.
class AppColors {
  // ────────────────────────────────────────────────────────────────────────────
  // Primary Brand Colors
  // ────────────────────────────────────────────────────────────────────────────

  /// Main brand color (e.g., Mint Green).
  static const Color primaryColor = Color(0xFF2CB4B6);
  static const Color black = Colors.black87;
  static const Color accentColor = Color(0xFFF67B0D);
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color primary = Color(0xFF2CB4B6);

  /// A slightly darker variant of the primary brand color.
  static const Color primaryDark = Color(0xFF239A9B);

  /// A slightly lighter variant of the primary brand color.
  static const Color primaryLight = Color(0xFF5DD3D4);

  // ────────────────────────────────────────────────────────────────────────────
  // Secondary / Accent Colors
  // ────────────────────────────────────────────────────────────────────────────

  /// Secondary accent color (e.g., Soft Yellow).
  static const Color secondary = Color(0xFFDAF6F7);

  /// A darker variant of the secondary accent color.
  static const Color secondaryDark = Color(0xFFB5E7E8);

  /// A lighter variant of the secondary accent color.
  static const Color secondaryLight = Color(0xFFEBFCFC);

  // ────────────────────────────────────────────────────────────────────────────
  // Neutral / Background Colors
  // ────────────────────────────────────────────────────────────────────────────

  /// App background color (pure white).
  static const Color background = Color(0xFFFFFFFF);

  /// Secondary background or card surface color (light gray).
  static const Color surface = Color(0xFFF5F5F5);

  /// Overlay or disabled container color (slightly darker gray).
  static const Color surfaceDark = Color(0xFFE0E0E0);

  /// A very light neutral for subtle backgrounds.
  static const Color neutralLight = Color(0xFFFAFAFA);

  // ────────────────────────────────────────────────────────────────────────────
  // Text Colors
  // ────────────────────────────────────────────────────────────────────────────

  /// Primary text color (dark gray / nearly black).
  static const Color textPrimary = Color(0xFF212121);

  /// Secondary text color (medium gray).
  static const Color textSecondary = Color(0xFF757575);

  /// Tertiary text or disabled text (light gray).
  static const Color textLight = Color(0xFFBDBDBD);

  /// Hint text or placeholder text.
  static const Color textHint = Color(0xFF9E9E9E);

  // ────────────────────────────────────────────────────────────────────────────
  // Icon & Border Colors
  // ────────────────────────────────────────────────────────────────────────────

  /// Standard icon color for interactive elements.
  static const Color iconDefault = Color(0xFF616161);

  /// Divider and border color (light gray).
  static const Color border = Color(0xFFEEEEEE);

  /// A slightly darker border or divider color.
  static const Color borderDark = Color(0xFFBDBDBD);

  // ────────────────────────────────────────────────────────────────────────────
  // Status / Feedback Colors
  // ────────────────────────────────────────────────────────────────────────────

  /// Success messages, icons, etc. (green).
  static const Color success = Color(0xFF4CAF50);

  /// Warning messages, icons, etc. (orange).
  static const Color warning = Color(0xFFFF9800);

  /// Error messages, icons, etc. (red).
  static const Color error = Color(0xFFF44336);

  /// Info messages, icons, etc. (blue).
  static const Color info = Color(0xFF2196F3);

  // ────────────────────────────────────────────────────────────────────────────
  // Example Usage Variants
  // ────────────────────────────────────────────────────────────────────────────

  /// Button text color when on primary background.
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Button text color when on secondary background.
  static const Color onSecondary = textPrimary;

  /// Overlay color for disabled buttons or containers.
  static const Color disabledOverlay = Color(0x80FFFFFF);

  /// Transparent variant of primary (50% opacity).
  static const Color primaryTransparent = Color(0x802CB4B6);

  /// Transparent variant of secondary (50% opacity).
  static const Color secondaryTransparent = Color(0x80DAF6F7);
}
