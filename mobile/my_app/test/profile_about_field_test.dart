import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/widgets/profile_about_field.dart';
import 'package:my_app/shared/screens/public_profile_screen.dart';

void main() {
  testWidgets(
    'About is multiline, public-labelled and editable on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController(text: 'Existing description');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ProfileAboutField(
                  controller: controller,
                  textColor: Colors.black,
                  mutedColor: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('About'), findsOneWidget);
      expect(
        find.text('Visible to other users on your profile.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.minLines, 3);
      expect(field.maxLength, 500);
      await tester.enterText(find.byType(TextField), 'Updated About');
      expect(controller.text, 'Updated About');
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in PublicProfileRole.values) {
    test(
      'public $role About uses saved description and respects explicit clearing',
      () {
        expect(
          publicProfileDescription({'description': 'New', 'bio': 'Old'}, role),
          'New',
        );
        expect(publicProfileDescription({'bio': 'Legacy'}, role), 'Legacy');
        expect(
          publicProfileDescription({'description': '', 'bio': 'Old'}, role),
          contains('has not added'),
        );
      },
    );
  }
}
