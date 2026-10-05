import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ألوان التطبيق مطابقة لألوان منصة فهمت على الويب.
class AppColors {
  static const primary = Color(0xFF29B6F6);
  static const primaryDark = Color(0xFF087EBC);
  static const primaryLight = Color(0xFFE1F5FE);

  static const accent = Color(0xFFFF7043);
  static const accentLight = Color(0xFFFFE7DF);

  static const ink = Color(0xFF12232E);
  static const inkSoft = Color(0xFF1D3444);
  static const paper = Color(0xFFF7FAFC);
  static const paperDim = Color(0xFFEAF1F5);
  static const muted = Color(0xFF60707C);
  static const line = Color(0xFFDDE6EC);
  static const white = Color(0xFFFFFFFF);

  // Aliases kept for existing widgets so the whole app adopts the same
  // platform palette without changing every screen manually.
  static const emerald = primaryDark;
  static const emeraldDark = primaryDark;
  static const emeraldLight = primaryLight;
  static const gold = accent;
  static const goldLight = accentLight;
  static const coral = accent;
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.white,
        error: AppColors.coral,
      ),
      textTheme: GoogleFonts.tajawalTextTheme(base.textTheme).copyWith(
        headlineSmall: GoogleFonts.elMessiri(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        headlineMedium: GoogleFonts.elMessiri(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.tajawal(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: AppColors.line,
            width: 1.4,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: AppColors.line,
            width: 1.4,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.6,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: AppColors.primary,
        secondaryLabelStyle: const TextStyle(color: AppColors.white),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      useMaterial3: true,
    );
  }
}
