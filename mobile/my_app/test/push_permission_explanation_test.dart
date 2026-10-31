import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/widgets/push_permission_explanation.dart';

void main() {
  for (final acceptExplanation in [false, true]) {
    for (final nativePermission in [false, true]) {
      testWidgets(
        'rationale=$acceptExplanation native=$nativePermission never blocks app',
        (tester) async {
          var requested = 0;
          bool? allowed;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Setup'),
                    onPressed: () async {
                      allowed = await requestPushConsent(
                        context,
                        requestPermission: () async {
                          requested++;
                          return nativePermission;
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Setup'));
          await tester.pumpAndSettle();
          expect(requested, 0);
          expect(find.text('Stay updated with SwiftServe'), findsOneWidget);
          await tester.tap(
            find.text(acceptExplanation ? 'Continue' : 'Not now'),
          );
          await tester.pumpAndSettle();
          expect(requested, acceptExplanation ? 1 : 0);
          expect(allowed, acceptExplanation && nativePermission);
          expect(find.text('Setup'), findsOneWidget);
        },
      );
    }
  }
}
