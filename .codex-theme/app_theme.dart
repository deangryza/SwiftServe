import 'package:flutter/material.dart';

/// Shared white, yellow and charcoal styling for SwiftServe.
abstract final class AppTheme {
  static const yellow = Color(0xFFFFC72C);
  static const ink = Color(0xFF242424);
  static const muted = Color(0xFF666666);
  static const line = Color(0xFFE5E5E5);
  static const softYellow = Color(0xFFFFF3CC);

  static OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: yellow,
        onPrimary: ink,
        primaryContainer: softYellow,
        onPrimaryContainer: ink,
        secondary: ink,
        onSecondary: Colors.white,
        secondaryContainer: softYellow,
        onSecondaryContainer: ink,
        tertiary: muted,
        onTertiary: Colors.white,
        tertiaryContainer: softYellow,
        onTertiaryContainer: ink,
        surface: Colors.white,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: Color(0xFFF8F8F8),
        surfaceContainerHigh: Color(0xFFF4F4F4),
        surfaceContainerHighest: Color(0xFFEEEEEE),
        outline: muted,
        outlineVariant: line,
        error: ink,
        onError: Colors.white,
        errorContainer: softYellow,
        onErrorContainer: ink,
        inverseSurface: ink,
        onInverseSurface: Colors.white,
        inversePrimary: yellow,
        surfaceTint: Colors.transparent,
      ),
    );
    final button = ElevatedButton.styleFrom(
      backgroundColor: yellow,
      foregroundColor: ink,
      disabledBackgroundColor: softYellow,
      disabledForegroundColor: muted,
      elevation: 0,
      minimumSize: const Size(64, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      dividerColor: line,
      iconTheme: const IconThemeData(color: ink, size: 24),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        hintStyle: const TextStyle(color: muted),
        labelStyle: const TextStyle(color: muted),
        floatingLabelStyle: const TextStyle(color: ink),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _border(line),
        enabledBorder: _border(line),
        focusedBorder: _border(yellow, 2),
        errorBorder: _border(ink),
        focusedErrorBorder: _border(ink, 2),
        errorStyle: const TextStyle(color: ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: button),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: yellow,
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: ink,
        unselectedItemColor: muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: softYellow,
        selectedColor: yellow,
        side: BorderSide.none,
        shape: StadiumBorder(),
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: Colors.white),
        actionTextColor: yellow,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: softYellow,
        selectionHandleColor: ink,
      ),
    );
  }
}
