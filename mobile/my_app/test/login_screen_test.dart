import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/entry_screen.dart';
import 'package:my_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('login screen matches the redesigned content and dimensions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to continue to your account'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text("Don't have an account? "), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);

    expect(tester.getSize(find.byType(TextField).first), const Size(296, 46));
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Sign In')),
      const Size(296, 56),
    );
  });

  testWidgets('sign up returns to the account type chooser', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: EntryScreen()));
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('I need help'), findsOneWidget);
    expect(find.text('I want to earn'), findsOneWidget);
  });

  testWidgets('forgot password asks for an email before contacting Firebase', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();

    expect(
      find.text('Enter your email to reset your password.'),
      findsOneWidget,
    );
  });
}
