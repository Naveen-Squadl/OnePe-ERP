import 'package:flutter/material.dart';

/// OnePe visual language (brand guide "ONEPE VISUAL LANGUAGE"): OnePe Blue + Lime as primary
/// colours, Navy / Amber / Leaf / Cream / Coral as secondary, Manrope as the only typeface.
class AppColors {
  // Brand palette.
  static const blue = Color(0xFF084E8F); // OnePe Blue (primary)
  static const lime = Color(0xFFD3E278); // OnePe Lime (primary)
  static const navy = Color(0xFF183461);
  static const amber = Color(0xFFFCB017);
  static const leaf = Color(0xFF8EC640);
  static const cream = Color(0xFFF4F2D5);
  static const coral = Color(0xFFF26B4E);

  // Derived UI tokens (darker shades where the brand colour is used as text on white).
  static const blueLight = Color(0xFF3C7BBF);
  static const blueDark = navy;
  static const blueTint = Color(0xFFE6EEF7);
  static const blueTintBorder = Color(0xFFB8CCE3);
  static const onLime = navy;
  static const green = Color(0xFF2E7D32); // success / positive text
  static const greenDark = Color(0xFF1B5E20);
  static const price = blue;
  static const danger = Color(0xFFC8452A); // coral, darkened for legible text
  static const orange = Color(0xFFB26B00); // amber, darkened for legible text / icons
  static const amberText = Color(0xFF8A5A00);
  static const bg = Color(0xFFF3F5F9);
  static const card = Colors.white;
  static const border = Color(0xFFE2E7EF);
  static const muted = Color(0xFF5B6B85);
  static const text = navy;

  /// Kept for older call sites: brand headers are flat OnePe Blue, primary buttons flat Lime.
  static const headerGradient = LinearGradient(colors: [blue, blue]);
  static const greenGradient = LinearGradient(colors: [lime, lime]);

  /// Category dots / icon tiles (cycled by index) – brand secondary colours first.
  static const palette = [
    coral,
    Color(0xFFE09A00), // amber (deeper, visible on white)
    Color(0xFF6FA82E), // leaf (deeper)
    blue,
    navy,
    blueLight,
    Color(0xFFC8452A), // coral (deeper)
    Color(0xFF3E7D16), // leaf (deepest)
  ];
  static Color forIndex(int i) => palette[i % palette.length];
  static Color forKey(String key) => palette[key.codeUnits.fold(0, (a, b) => a + b) % palette.length];
}

class AppTheme {
  static const font = 'Manrope';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      primary: AppColors.blue,
      onPrimary: Colors.white,
      secondary: AppColors.lime,
      onSecondary: AppColors.navy,
      tertiary: AppColors.amber,
      error: AppColors.danger,
      surface: Colors.white,
      onSurface: AppColors.text,
    );
    final base = ThemeData(useMaterial3: true, fontFamily: font, colorScheme: scheme);
    final text = base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text);
    const radius14 = BorderRadius.all(Radius.circular(14));
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: AppColors.bg,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(fontFamily: font, color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      ),
      cardTheme: CardThemeData(
        elevation: 1.5,
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.navy.withValues(alpha: .18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(borderRadius: radius14),
        enabledBorder: const OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: Color(0xFFCCD5E2))),
        focusedBorder: const OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: AppColors.blue, width: 2)),
        labelStyle: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700),
        prefixIconColor: AppColors.muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: const RoundedRectangleBorder(borderRadius: radius14),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lime,
          foregroundColor: AppColors.navy,
          elevation: 0,
          minimumSize: const Size(0, 48),
          shape: const RoundedRectangleBorder(borderRadius: radius14),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: Color(0xFFC9D3E1)),
          minimumSize: const Size(0, 46),
          shape: const RoundedRectangleBorder(borderRadius: radius14),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.blue, textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))))),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: AppColors.border),
        selectedColor: AppColors.blue,
        checkmarkColor: Colors.white,
        secondaryLabelStyle: const TextStyle(fontFamily: font, color: Colors.white, fontWeight: FontWeight.w700),
        labelStyle: const TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.lime,
          selectedForegroundColor: AppColors.navy,
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: Color(0xFFC9D3E1)),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.lime,
        foregroundColor: AppColors.navy,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
        extendedTextStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: 15),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: const TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: font, color: AppColors.navy, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(fontFamily: font, color: Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: AppColors.lime,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Color(0xFFC9D6EA),
        indicatorColor: AppColors.lime,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w800),
        unselectedLabelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
        dividerColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.blue : null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.blue : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.blue),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.navy, textColor: AppColors.navy),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.navy,
        indicatorColor: AppColors.blue,
        selectedIconTheme: IconThemeData(color: AppColors.lime),
        unselectedIconTheme: IconThemeData(color: Color(0xFFB9C4D8)),
        selectedLabelTextStyle: TextStyle(fontFamily: font, color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelTextStyle: TextStyle(fontFamily: font, color: Color(0xFFB9C4D8), fontWeight: FontWeight.w600, fontSize: 11),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.blue,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}

/// Status colours used across bills / stock / customers.
class StatusColors {
  static const due = AppColors.danger;
  static const advance = AppColors.green;
  static const waiting = Color(0xFFB26B00);
  static const ok = AppColors.green;
  static const muted = AppColors.muted;
}
