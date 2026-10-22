import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/widgets/notification_swipe_actions.dart';

void main() {
  Widget subject({
    required VoidCallback onViewDetails,
    required VoidCallback onDelete,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: NotificationSwipeActions(
            key: const ValueKey('swipe-host'),
            actionKeyPrefix: 'test-notification',
            onViewDetails: onViewDetails,
            onDelete: onDelete,
            child: const SizedBox(
              height: 94,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'completed left swipe invokes View Details without an extra tap',
    (tester) async {
      var viewed = false;
      await tester.pumpWidget(
        subject(onViewDetails: () => viewed = true, onDelete: () {}),
      );

      await tester.drag(
        find.byKey(const ValueKey('test-notification-gesture')),
        const Offset(-90, 0),
      );
      await tester.pumpAndSettle();

      expect(viewed, isTrue);
    },
  );

  testWidgets('completed right swipe invokes Delete without an extra tap', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      subject(onViewDetails: () {}, onDelete: () => deleted = true),
    );

    await tester.drag(
      find.byKey(const ValueKey('test-notification-gesture')),
      const Offset(90, 0),
    );
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });

  testWidgets('short horizontal swipes return without invoking an action', (
    tester,
  ) async {
    var deleted = false;
    var viewed = false;
    await tester.pumpWidget(
      subject(
        onViewDetails: () => viewed = true,
        onDelete: () => deleted = true,
      ),
    );

    final gesture = find.byKey(const ValueKey('test-notification-gesture'));
    await tester.drag(gesture, const Offset(-30, 0));
    await tester.pumpAndSettle();
    await tester.drag(gesture, const Offset(30, 0));
    await tester.pumpAndSettle();

    expect(deleted, isFalse);
    expect(viewed, isFalse);
  });
}
