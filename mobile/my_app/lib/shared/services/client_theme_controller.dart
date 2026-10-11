import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientThemeController {
  ClientThemeController._();

  static const _storageKey = 'swiftserve_client_dark_mode';
  static final ValueNotifier<bool> darkMode = ValueNotifier(false);

  static Future<void> initialize() async {
    darkMode.value =
        await SharedPreferencesAsync().getBool(_storageKey) ?? false;
  }

  static Future<void> setDarkMode(bool enabled) async {
    darkMode.value = enabled;
    await SharedPreferencesAsync().setBool(_storageKey, enabled);
  }
}

class ClientThemeScope extends StatelessWidget {
  const ClientThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ClientThemeController.darkMode,
    builder: (context, darkMode, child) =>
        Theme(data: darkMode ? _darkTheme : _lightTheme, child: child!),
    child: child,
  );

  static final _lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFFC72C),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFFFF9E9),
    useMaterial3: true,
  );

  static final _darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFFC72C),
      brightness: Brightness.dark,
      surface: const Color(0xFF242424),
    ),
    scaffoldBackgroundColor: const Color(0xFF171717),
    cardColor: const Color(0xFF2C2C2C),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF242424),
      foregroundColor: Color(0xFFF2F2F2),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF242424),
      indicatorColor: Color(0xFFFFC72C),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2C2C2C),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    useMaterial3: true,
  );
}
