import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/client_register_screen.dart';
import 'package:my_app/features/auth/presentation/screens/entry_screen.dart';
import 'package:my_app/features/auth/presentation/screens/login_screen.dart';
import 'package:my_app/features/auth/presentation/screens/worker_register_screen.dart';

void main() {
  testWidgets('entry screen matches the Figma control geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: EntryScreen()));

    expect(find.text('SwiftServe'), findsOneWidget);
    expect(
      find.text('Get help nearby. Earn with your skills.'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'I need help')),
      const Size(260, 55),
    );
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'I want to earn')),
      const Size(260, 57),
    );
    expect(find.text('Already have an account? '), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('entry actions preserve the existing destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: EntryScreen()));

    await tester.tap(find.text('I need help'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientRegisterScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('I want to earn'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkerRegisterScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
