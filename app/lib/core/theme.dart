import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Visual language: blue gradient headers, white rounded cards, green gradient
/// primary actions, Poppins typography.
class AppColors {
  static const blue = Color(0xFF2F80ED);
  static const blueLight = Color(0xFF56CCF2);
  static const blueDark = Color(0xFF1E6FD9);
  static const green = Color(0xFF12A46A);
  static const greenDark = Color(0xFF0B8A57);
  static const price = Color(0xFF119A5B);
  static const danger = Color(0xFFE53935);
  static const orange = Color(0xFFF2994A);
  static const bg = Color(0xFFF7F8FA);
  static const card = Colors.white;
  static const border = Color(0xFFE8EBF0);
  static const muted = Color(0xFF7A808C);
  static const text = Color(0xFF1F2430);

  static const headerGradient = LinearGradient(colors: [blue, blueLight]);
  static const greenGradient = LinearGradient(colors: [Color(0xFF15B57A), greenDark]);

  /// Category chip / badge palette (cycled by index).
  static const palette = [
    Color(0xFFE53958), // rose
    Color(0xFFF2994A), // orange
    Color(0xFF12A46A), // green
    Color(0xFF2F80ED), // blue
    Color(0xFF9B51E0), // purple
    Color(0xFF00A3BF), // teal
    Color(0xFFEB5757), // red
    Color(0xFFD4A017), // amber
  ];
  static Color forIndex(int i) => palette[i % palette.length];
  static Color forKey(String key) => palette[key.codeUnits.fold(0, (a, b) => a + b) % palette.length];
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.blue, primary: AppColors.blue, surface: Colors.white);
    final text = GoogleFonts.poppinsTextTheme().apply(bodyColor: AppColors.text, displayColor: AppColors.text);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: text,
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF9AA0AA))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        labelStyle: GoogleFonts.poppins(fontSize: 13),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        extendedTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      dialogTheme: DialogThemeData(backgroundColor: const Color(0xFFF1F3F7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        dividerColor: Colors.transparent,
      ),
    );
  }
}

/// Status colours used across bills / stock / customers.
class StatusColors {
  static const due = AppColors.danger;
  static const advance = AppColors.green;
  static const waiting = Color(0xFFEF6C00);
  static const ok = AppColors.green;
  static const muted = AppColors.muted;
}
