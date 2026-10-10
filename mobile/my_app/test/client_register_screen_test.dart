import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:my_app/features/auth/presentation/screens/client_register_screen.dart';

void main() {
  testWidgets('client registration uses the shared Figma design', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ClientRegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsNWidgets(2));
    expect(find.text('Signing up as Client'), findsOneWidget);
    expect(find.text('Signing up as Worker'), findsNothing);
    expect(find.text('Primary Service Category'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.text('Home'), findsNothing);
    expect(find.text('History'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('client registration fields accept and display input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(364, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ClientRegisterScreen()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alex Client');
    await tester.enterText(fields.at(1), 'client@example.com');

    expect(find.text('Alex Client'), findsOneWidget);
    expect(find.text('client@example.com'), findsOneWidget);
  });
}
