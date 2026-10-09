import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/entry_screen.dart';
import 'package:my_app/features/onboarding/presentation/screens/onboarding_screen.dart';

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
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    expect(find.text('I need help'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Find Nearby Services Easily'), findsOneWidget);
  });
}
