import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette: nero sfumato al grigio, accenti bianco/argento.
class AppColors {
  static const black = Color(0xFF0A0A0A);
  static const charcoal = Color(0xFF161616);
  static const graphite = Color(0xFF242424);
  static const steel = Color(0xFF353535);
  static const silver = Color(0xFFBDBDBD);
  static const muted = Color(0xFF8E8E8E);
  static const white = Color(0xFFEDE8DF); // avorio: tono caldo da insegna vintage
  static const success = Color(0xFF7BC98F);
  static const danger = Color(0xFFE57373);
  static const warning = Color(0xFFE0B862);

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [black, charcoal, Color(0xFF2B2B2B)],
    stops: [0, 0.55, 1],
  );

  static Color card = Colors.white.withValues(alpha: 0.05);
  static Color cardBorder = Colors.white.withValues(alpha: 0.10);
}

TextStyle slab({double size = 18, FontWeight weight = FontWeight.w500, Color? color, double spacing = 1.2}) =>
    GoogleFonts.robotoSlab(fontSize: size, fontWeight: weight, color: color ?? AppColors.white, letterSpacing: spacing);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.white,
      onPrimary: AppColors.black,
      secondary: AppColors.silver,
      onSecondary: AppColors.black,
      surface: AppColors.charcoal,
      onSurface: AppColors.white,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.black,
  );
  final text = GoogleFonts.exo2TextTheme(base.textTheme).apply(
    bodyColor: AppColors.white,
    displayColor: AppColors.white,
  );
  final radius = BorderRadius.circular(6);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: slab(size: 18, weight: FontWeight.w600),
      foregroundColor: AppColors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.black,
        disabledBackgroundColor: AppColors.steel,
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: GoogleFonts.exo2(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.white,
        minimumSize: const Size(64, 50),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: GoogleFonts.exo2(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.silver,
        textStyle: GoogleFonts.exo2(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      labelStyle: const TextStyle(color: AppColors.muted),
      floatingLabelStyle: const TextStyle(color: AppColors.silver),
      prefixIconColor: AppColors.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      focusedBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.silver)),
      errorBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.danger)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.graphite,
      contentTextStyle: GoogleFonts.exo2(color: AppColors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.charcoal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: slab(size: 19, weight: FontWeight.w600),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.charcoal,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08), space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      selectedColor: AppColors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      labelStyle: GoogleFonts.exo2(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.black,
      indicatorColor: Colors.white.withValues(alpha: 0.12),
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.exo2(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.white.withValues(alpha: 0.12),
      selectedLabelTextStyle: GoogleFonts.exo2(fontWeight: FontWeight.w700, color: AppColors.white),
      unselectedLabelTextStyle: GoogleFonts.exo2(color: AppColors.muted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.black : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.white : AppColors.graphite),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.white : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(AppColors.black),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.white),
  );
}
