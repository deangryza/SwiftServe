import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/login_screen.dart';
import 'package:my_app/shared/services/client_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => ClientThemeController.darkMode.value = false);

  for (final size in [
    const Size(320, 568),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('login fits $size and signup opens role selection', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: const LoginScreen(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
      final google = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('google-login-preview')),
      );
      expect(google.onPressed, isNotNull);
      final signup = find.byKey(const ValueKey('login-sign-up'));
      await tester.ensureVisible(signup);
      await tester.pumpAndSettle();
      await tester.tap(signup);
      await tester.pumpAndSettle();
      expect(find.text('I need help'), findsOneWidget);
      expect(find.text('I want to earn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('login applies the saved dark palette with readable fields', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'has_signed_in_before': true});
    ClientThemeController.darkMode.value = true;

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF242424));
    expect(
      tester.widget<Text>(find.text('Welcome back')).style?.color,
      const Color(0xFF242424),
    );
    final email = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('login-email')),
        matching: find.byType(TextField),
      ),
    );
    expect(email.decoration?.fillColor, const Color(0xFF2C2C2C));
    expect(email.style?.color, const Color(0xFFF7F7F7));
  });

  testWidgets('password visibility toggle shows and hides the password', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    TextField passwordField() => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('login-password')),
        matching: find.byType(TextField),
      ),
    );

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('login-password-toggle')));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
    await tester.tap(find.byKey(const ValueKey('login-password-toggle')));
    await tester.pump();
    expect(passwordField().obscureText, isTrue);
  });
}
