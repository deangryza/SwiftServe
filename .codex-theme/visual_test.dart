import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/theme/app_theme.dart';
import 'package:my_app/screens/onboarding/onboarding_screen.dart';
import 'package:my_app/entry/entry_screen.dart';
import 'package:my_app/auth/login_screen.dart';
import 'package:my_app/auth/client_register_screen.dart';

void main() {
  testWidgets('Existing screens render with the simplified theme', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('Ahem')..addFont(
        File('C:/Windows/Fonts/segoeui.ttf').readAsBytes().then(ByteData.sublistView),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons')..addFont(
        File('C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then(ByteData.sublistView),
      );
      await icons.load();
    });
    tester.view.devicePixelRatio = 1;
    final handler = FlutterError.onError!;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      handler(details);
    };
    addTearDown(() => FlutterError.onError = handler);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final screens = <String, Widget>{
      'onboarding': const OnboardingScreen(),
      'entry': const EntryScreen(),
      'login': const LoginScreen(),
      'register': const ClientRegisterScreen(),
    };
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      tester.view.physicalSize = size;
      for (final scale in [1.0, 2.0]) {
        for (final screen in screens.entries) {
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true,
              ),
              child: child!,
            ),
            home: RepaintBoundary(key: key, child: screen.value),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
            reason: '${screen.key} at $size, scale $scale');
          if (size.width == 375 && scale == 1) {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(format: ImageByteFormat.png);
              await File('C:/Users/User/Documents/SwiftServe/.codex-theme/${screen.key}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });
}
