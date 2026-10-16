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

  testWidgets('entry screen uses its dark palette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: const EntryScreen()),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF171717));
    final title = tester.widget<Text>(find.text('SwiftServe'));
    expect(title.style?.color, const Color(0xFFF3F3F3));
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
    final nearbyImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('onboarding-illustration-0')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (nearbyImage.image as AssetImage).assetName,
      'assets/onboarding/onboarding_nearby_light.png',
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('Turn your Skills into\nOpportunities'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('onboarding-illustration-1')),
      findsOneWidget,
    );
    final skillsImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('onboarding-illustration-1')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (skillsImage.image as AssetImage).assetName,
      'assets/onboarding/onboarding_skills_light.png',
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('I need help'), findsOneWidget);
    expect(find.text('I want to earn'), findsOneWidget);
  });

  testWidgets('onboarding uses its dark palette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const SwiftServeOnboardingScreen(),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF171717));
    final title = tester.widget<Text>(find.text('Find Nearby Services Easily'));
    expect(title.style?.color, const Color(0xFFF3F3F3));
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('onboarding-illustration-0')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/onboarding/onboarding_nearby_dark.png',
    );
  });
}
