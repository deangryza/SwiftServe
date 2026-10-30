import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/profile_photo_picker.dart';

void main() {
  for (final choice in ['Not now', 'Allow', 'dismiss']) {
    testWidgets('photo picker is gated by consent: $choice', (tester) async {
      var picks = 0;
      Uint8List? result;
      final photo = Uint8List.fromList([1, 2, 3]);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await pickProfilePhotoWithConsent(
                      context,
                      pickPhoto: () async {
                        picks++;
                        return photo;
                      },
                    );
                  },
                  child: const Text('Change photo'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      expect(find.text('Allow photo selection?'), findsOneWidget);
      expect(picks, 0);
      if (choice == 'dismiss') {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
      } else {
        await tester.tap(find.text(choice));
      }
      await tester.pumpAndSettle();
      expect(picks, choice == 'Allow' ? 1 : 0);
      expect(result, choice == 'Allow' ? photo : isNull);
    });
  }

  for (final denial in [false, true]) {
    testWidgets(
      'gallery ${denial ? 'denial' : 'cancellation'} leaves no selected photo',
      (tester) async {
        Uint8List? result;
        Object? error;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      try {
                        result = await pickProfilePhotoWithConsent(
                          context,
                          pickPhoto: () async {
                            if (denial) {
                              throw PlatformException(
                                code: 'photo_access_denied',
                              );
                            }
                            return null;
                          },
                        );
                      } catch (failure) {
                        error = failure;
                      }
                    },
                    child: const Text('Change photo'),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Change photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Allow'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(error, denial ? isA<FormatException>() : isNull);
      },
    );
  }
}
