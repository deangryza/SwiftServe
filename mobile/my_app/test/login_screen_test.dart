import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('login fits $size and signup opens role selection', (
      tester,
    ) async {
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
      expect(find.text('Welcome back'), findsOneWidget);
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
}
