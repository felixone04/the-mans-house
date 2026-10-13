import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';

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

  /// Pulsanti discreti in grigio (home: prenota e account).
  static const quiet = Color(0xFF262626);
  static const quietBorder = Color(0xFF3A3A3A);
  static const quietText = Color(0xFFD6D6D6);

  /// Un colore per barbiere in agenda (toni smorzati, leggibili sul nero).
  static const barberPalette = [
    Color(0xFF5DCAA5), // verde acqua
    Color(0xFFF0997B), // corallo
    Color(0xFF85B7EB), // azzurro
    Color(0xFFAFA9EC), // lilla
    Color(0xFFEFB45F), // ambra
    Color(0xFFED93B1), // rosa
    Color(0xFF97C459), // verde
  ];
}

/// Colori chiari dell'agenda da telefono.
class AgendaLight {
  static const paper = Color(0xFFF6F5F2);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C1C1C);
  static const sub = Color(0xFF5F5F5F);
  static const muted = Color(0xFF9A9A9A);
  static const line = Color(0xFFE3E1DB);
  static const now = Color(0xFFD33A3A);
  static const ok = Color(0xFF1D9E75);
  static const warn = Color(0xFFB36B00);
}

/// Toni pastello di un barbiere: sfondo, testo secondario, accento, testo.
typedef BarberTone = ({Color bg, Color mid, Color accent, Color ink});

const _tones = <BarberTone>[
  (bg: Color(0xFFE1F5EE), mid: Color(0xFF0F6E56), accent: Color(0xFF1D9E75), ink: Color(0xFF04342C)),
  (bg: Color(0xFFFAECE7), mid: Color(0xFF993C1D), accent: Color(0xFFD85A30), ink: Color(0xFF4A1B0C)),
  (bg: Color(0xFFE6F1FB), mid: Color(0xFF185FA5), accent: Color(0xFF378ADD), ink: Color(0xFF042C53)),
  (bg: Color(0xFFEEEDFE), mid: Color(0xFF534AB7), accent: Color(0xFF7F77DD), ink: Color(0xFF26215C)),
  (bg: Color(0xFFFAEEDA), mid: Color(0xFF854F0B), accent: Color(0xFFBA7517), ink: Color(0xFF412402)),
  (bg: Color(0xFFFBEAF0), mid: Color(0xFF993556), accent: Color(0xFFD4537E), ink: Color(0xFF4B1528)),
  (bg: Color(0xFFEAF3DE), mid: Color(0xFF3B6D11), accent: Color(0xFF639922), ink: Color(0xFF173404)),
];

BarberTone barberTone(List<Barber> barbers, String barberId) {
  final i = barbers.indexWhere((b) => b.id == barberId);
  return _tones[(i < 0 ? 0 : i) % _tones.length];
}

/// Colore del barbiere in base alla sua posizione nell'elenco.
Color barberColor(List<Barber> barbers, String barberId) {
  final i = barbers.indexWhere((b) => b.id == barberId);
  return i < 0 ? AppColors.muted : AppColors.barberPalette[i % AppColors.barberPalette.length];
}

/// Nei test i caratteri non si scaricano: si usa il carattere predefinito.
bool googleFontsEnabled = true;

TextStyle slab({double size = 18, FontWeight weight = FontWeight.w500, Color? color, double spacing = 1.2}) =>
    googleFontsEnabled
    ? GoogleFonts.robotoSlab(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.white,
        letterSpacing: spacing,
      )
    : TextStyle(fontSize: size, fontWeight: weight, color: color ?? AppColors.white, letterSpacing: spacing);

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
  final text = GoogleFonts.exo2TextTheme(base.textTheme)
      .apply(bodyColor: AppColors.white, displayColor: AppColors.white);
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
        borderRadius: radius,
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.silver),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.danger),
      ),
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
        (s) => s.contains(WidgetState.selected) ? AppColors.black : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.white : AppColors.graphite,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.white : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.black),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.white),
  );
}
