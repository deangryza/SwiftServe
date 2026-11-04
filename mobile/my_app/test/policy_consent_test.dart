import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/widgets/policy_consent.dart';
import 'package:my_app/features/auth/presentation/widgets/policy_dialog.dart';
import 'package:my_app/shared/theme/app_theme.dart';

void main() {
  testWidgets(
    'security policy has full content and shares consent with terms',
    (tester) async {
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
      await openTerms(tester, security: true);
      expect(find.text('19. ACKNOWLEDGMENT'), findsOneWidget);
      expect(find.text('2.1 Authentication'), findsOneWidget);
      expect(
        find.textContaining('[Insert Official Security Email]'),
        findsNWidgets(2),
      );
      expect(accepted, isFalse);
      await tester.tap(find.byKey(const ValueKey('policy-expand')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Restore popup size'), findsOneWidget);
      final inside = find.byKey(const ValueKey('security-dialog-consent'));
      await tester.ensureVisible(inside);
      await tester.pumpAndSettle();
      await tester.tap(inside);
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('policy-consent-checkbox')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('policy-close')));
      await tester.pumpAndSettle();
      await openTerms(tester);
      final terms = find.byKey(const ValueKey('terms-dialog-consent'));
      await tester.ensureVisible(terms);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(terms).value, isTrue);
      await tester.tap(terms);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('policy-close')));
      await tester.pumpAndSettle();
      await openTerms(tester, security: true);
      await tester.ensureVisible(inside);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(inside).value, isFalse);
      await tester.tap(find.byKey(const ValueKey('policy-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'terms consent stays synchronized through expand, close and reopen',
    (tester) async {
      var accepted = false;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return PolicyConsent(
                  value: accepted,
                  enabled: enabled,
                  onChanged: (value) => setState(() => accepted = value),
                );
              },
            ),
          ),
        ),
      );
      await openTerms(tester);
      expect(find.text('25. ACCEPTANCE'), findsOneWidget);
      expect(find.textContaining('[Insert Date]'), findsOneWidget);
      expect(
        find.textContaining('[Insert Official Support Email]'),
        findsOneWidget,
      );
      final normalWidth = tester
          .getSize(find.byKey(const ValueKey('policy-sheet')))
          .width;
      await tester.tap(find.byKey(const ValueKey('policy-expand')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('policy-sheet'))).width,
        greaterThan(normalWidth),
      );
      expect(find.byTooltip('Restore popup size'), findsOneWidget);
      final inside = find.byKey(const ValueKey('terms-dialog-consent'));
      await tester.ensureVisible(inside);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(inside).value, isFalse);
      await tester.tap(inside);
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(tester.widget<CheckboxListTile>(inside).value, isTrue);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('policy-consent-checkbox')),
            )
            .value,
        isTrue,
      );
      // An external state update also reaches the already-open popup.
      update(() => accepted = false);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(inside).value, isFalse);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(inside).onChanged, isNull);
      update(() => enabled = true);
      await tester.pumpAndSettle();
      await tester.tap(inside);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('policy-close')));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      await openTerms(tester);
      await tester.ensureVisible(inside);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(inside).value, isTrue);
      await tester.tap(inside);
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      await tester.tap(find.byKey(const ValueKey('policy-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long terms popup fits narrow dark screens with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: PolicyConsent(value: false, onChanged: (_) {}),
          ),
        ),
      ),
    );
    await openTerms(tester);
    await tester.tap(find.byKey(const ValueKey('policy-expand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('policy-expand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('policy-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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
      expect(find.widgetWithText(PolicyDialog, title), findsOneWidget);
      expect(accepted, isFalse);
      await tester.tap(find.byKey(const ValueKey('policy-close')));
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

Future<void> openTerms(WidgetTester tester, {bool security = false}) async {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(PolicyConsent),
      matching: find.byType(Text),
    ),
  );
  final span = (text.textSpan! as TextSpan).children!
      .whereType<TextSpan>()
      .singleWhere(
        (span) =>
            span.text ==
            (security ? 'Security Policy' : 'Terms and Conditions'),
      );
  (span.recognizer! as TapGestureRecognizer).onTap!();
  await tester.pumpAndSettle();
}
