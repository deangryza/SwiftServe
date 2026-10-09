import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:my_app/features/auth/presentation/screens/worker_register_screen.dart';

void main() {
  testWidgets('worker registration uses the Figma layout and worker role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsNWidgets(2));
    expect(find.text('Join our professional service network'), findsOneWidget);
    expect(find.text('Signing up as Worker'), findsOneWidget);
    expect(
      find.text(
        'To ensure community safety, all users must verify their identity.',
      ),
      findsOneWidget,
    );
    expect(find.text('Primary Service Category'), findsOneWidget);
    expect(
      find.text('Your data is encrypted and stored securely.'),
      findsOneWidget,
    );
    expect(find.byType(SvgPicture), findsWidgets);
  });

  testWidgets('worker registration keeps all required account fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(7));
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Address / Location'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('worker registration fields accept and display input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alex Worker');
    await tester.enterText(fields.at(1), 'alex@example.com');
    await tester.enterText(fields.at(2), '09171234567');
    await tester.enterText(fields.at(3), '123 Service Lane');
    await tester.enterText(fields.at(4), 'Plumbing');

    expect(find.text('Alex Worker'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
    expect(find.text('123 Service Lane'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
  });
}
