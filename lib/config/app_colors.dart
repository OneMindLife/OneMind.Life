import 'package:flutter/material.dart';

/// Semantic color palette for OneMind.
///
/// Warm civic direction: deep indigo for trust + amber/gold for consensus.
class AppColors {
  AppColors._();

  // Primary: deep indigo (trust, wisdom)
  static const seed = Color(0xFF6366F1);

  // Warm accent: amber/gold (consensus, achievement, warmth)
  static const consensus = Color(0xFFF59E0B);
  static const consensusLight = Color(0xFFFEF3C7);

  // Phase colors
  static const proposing = Color(0xFF8B5CF6); // violet - open, creative
  static const rating = Color(0xFF3B82F6); // blue - focused, deliberate
  static const waiting = Color(0xFF6B7280); // warm gray - calm, patient

  // Warm neutrals (replace cold grays)
  static const textPrimary = Color(0xFF1F2937); // gray-800 warm
  static const textSecondary = Color(0xFF6B7280); // gray-500 warm
  static const textMuted = Color(0xFF9CA3AF); // gray-400 warm
  static const surfaceWarm = Color(0xFFFAFAF8); // slightly warm white
  static const borderWarm = Color(0xFFE5E5E3); // warm border

  // Dark mode warm neutrals
  static const darkSurface = Color(0xFF1A1A1E); // warm dark
  static const darkSurfaceContainer = Color(0xFF242428); // warm dark container
  static const darkBorder = Color(0xFF3A3A3E); // warm dark border
}
