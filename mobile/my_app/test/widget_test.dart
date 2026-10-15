import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/entry_screen.dart';
import 'package:my_app/features/onboarding/presentation/screens/swiftserve_onboarding_screen.dart';

void main() {
  testWidgets('canonical entry screen exposes both roles', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EntryScreen()));

    expect(find.text('SwiftServe'), findsOneWidget);
    expect(find.text('I need help'), findsOneWidget);
    expect(find.text('I want to earn'), findsOneWidget);
    expect(find.text('Already have an account? '), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('entry flow preserves the root auth-gate route', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SwiftServeOnboardingScreen()),
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('I need help'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Find Nearby Services Easily'), findsOneWidget);
  });

  testWidgets('onboarding next and get started open role selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: SwiftServeOnboardingScreen()),
    );

    expect(find.text('Find Nearby Services Easily'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-illustration-0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('Turn your Skills into\nOpportunities'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-illustration-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('I need help'), findsOneWidget);
    expect(find.text('I want to earn'), findsOneWidget);
  });
}
