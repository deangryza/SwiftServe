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

Route<T> clientPageRoute<T>(Widget page) =>
    MaterialPageRoute<T>(builder: (_) => ClientThemeScope(child: page));

Route<T> clientTabPageRoute<T>(
  Widget page, {
  required int fromIndex,
  required int toIndex,
}) {
  final horizontalOffset = toIndex > fromIndex ? 0.08 : -0.08;
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => ClientThemeScope(child: page),
    transitionsBuilder: (_, animation, _, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        key: const ValueKey('client-tab-transition'),
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(horizontalOffset, 0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class ClientTabSwipeRegion extends StatefulWidget {
  const ClientTabSwipeRegion({
    super.key,
    required this.currentIndex,
    required this.onSwipeToIndex,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onSwipeToIndex;
  final Widget child;

  @override
  State<ClientTabSwipeRegion> createState() => _ClientTabSwipeRegionState();
}

class _ClientTabSwipeRegionState extends State<ClientTabSwipeRegion> {
  static const _distanceThreshold = 54.0;
  static const _velocityThreshold = 500.0;
  double _horizontalDistance = 0;

  void _finishSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final movesForward =
        _horizontalDistance <= -_distanceThreshold ||
        velocity <= -_velocityThreshold;
    final movesBackward =
        _horizontalDistance >= _distanceThreshold ||
        velocity >= _velocityThreshold;
    _horizontalDistance = 0;

    final targetIndex = movesForward
        ? widget.currentIndex + 1
        : movesBackward
        ? widget.currentIndex - 1
        : widget.currentIndex;
    if (targetIndex >= 0 &&
        targetIndex <= 3 &&
        targetIndex != widget.currentIndex) {
      widget.onSwipeToIndex(targetIndex);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _horizontalDistance = 0,
    onHorizontalDragUpdate: (details) =>
        _horizontalDistance += details.primaryDelta ?? 0,
    onHorizontalDragCancel: () => _horizontalDistance = 0,
    onHorizontalDragEnd: _finishSwipe,
    child: widget.child,
  );
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
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
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
    dividerColor: const Color(0xFF494949),
    cardTheme: const CardThemeData(
      color: Color(0xFF2C2C2C),
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF2C2C2C),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Color(0xFFF3F3F3),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: Color(0xFFB8B8B8)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF242424),
      modalBackgroundColor: Color(0xFF242424),
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF343434),
      contentTextStyle: TextStyle(color: Color(0xFFF3F3F3)),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Color(0xFF2C2C2C),
      surfaceTintColor: Colors.transparent,
    ),
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
      labelStyle: const TextStyle(color: Color(0xFFB8B8B8)),
      hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    useMaterial3: true,
  );
}
