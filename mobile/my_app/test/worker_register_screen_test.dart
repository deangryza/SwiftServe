import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/screens/worker_register_screen.dart';
import 'package:my_app/shared/services/client_theme_controller.dart';

void main() {
  tearDown(() => ClientThemeController.darkMode.value = false);

  testWidgets('worker registration uses the Figma layout and worker role', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Join our professional service network'), findsOneWidget);
    expect(find.text('Signing up as Worker'), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Last Name'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Home'), findsNothing);
    expect(find.text('History'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('worker registration next opens credentials', (tester) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alex');
    await tester.enterText(fields.at(1), 'Worker');
    await _tapNext(tester);

    expect(find.byType(TextFormField), findsNWidgets(5));
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Address / Location'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets(
    'worker next buttons traverse the placeholder verification flow',
    (tester) async {
      tester.view.physicalSize = const Size(364, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
      await tester.pumpAndSettle();

      var fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Alex');
      await tester.enterText(fields.at(1), 'Worker');
      await _tapNext(tester);

      fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'alex@example.com');
      await tester.enterText(fields.at(1), '09171234567');
      await tester.enterText(fields.at(2), '123 Service Lane');
      await tester.enterText(fields.at(3), 'password');
      await tester.enterText(fields.at(4), 'password');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await _tapNext(tester);

      expect(find.text('Service Categories'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('worker-category-Electrical')),
      );
      await _tapNext(tester);
      expect(find.text('Enter code'), findsOneWidget);

      await _tapNext(tester);
      expect(find.text('Government ID'), findsOneWidget);
      await _tapNext(tester);
      expect(find.text('Face Recognition'), findsOneWidget);
      await _tapNext(tester);
      expect(find.text('Verification in Progress'), findsOneWidget);
      expect(find.text('Identity Check'), findsOneWidget);
      expect(find.text('Certificates'), findsOneWidget);
    },
  );

  testWidgets('worker registration applies the readable dark palette', (
    tester,
  ) async {
    ClientThemeController.darkMode.value = true;
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WorkerRegisterScreen()));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF242424));
    expect(
      tester.widget<Text>(find.text('Create Account')).style?.color,
      const Color(0xFFF2F2F2),
    );
    final firstName = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('worker-First Name')),
        matching: find.byType(TextField),
      ),
    );
    expect(firstName.style?.color, const Color(0xFFF2F2F2));
    expect(firstName.decoration?.fillColor, const Color(0xFF2C2C2C));
  });
}

Future<void> _tapNext(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('worker-registration-next'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
