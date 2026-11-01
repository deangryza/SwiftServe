import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/widgets/policy_consent.dart';
import 'package:my_app/shared/theme/app_theme.dart';

void main() {
  testWidgets('checkbox is explicit and each link opens its own policy', (
    tester,
  ) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PolicyConsent(
              value: accepted,
              onChanged: (value) => setState(() => accepted = value),
            ),
          ),
        ),
      ),
    );
    for (final title in ['Terms and Conditions', 'Security Policy']) {
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(PolicyConsent),
          matching: find.byType(Text),
        ),
      );
      final span = (text.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.text == title);
      (span.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AlertDialog, title), findsOneWidget);
      expect(accepted, isFalse);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(accepted, isTrue);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(accepted, isFalse);
  });

  testWidgets(
    'consent wraps at narrow width with large text and disabled input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: PolicyConsent(
                value: false,
                enabled: false,
                showError: true,
                onChanged: (_) => fail('Disabled checkbox must not change'),
              ),
            ),
          ),
        ),
      );
      expect(find.text(PolicyConsent.requiredMessage), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
