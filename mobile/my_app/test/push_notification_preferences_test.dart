import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/theme/app_theme.dart';
import 'package:my_app/shared/widgets/push_notification_preferences.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'notification cards match settings in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var systemSettingsOpened = false;
        const channel = MethodChannel('swiftserve/notification_settings');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            expect(call.method, 'open');
            systemSettingsOpened = true;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : AppTheme.light,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: const SingleChildScrollView(
                  padding: EdgeInsets.all(22),
                  child: PushNotificationPreferences(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in ['enabled', 'chats', 'activities', 'system']) {
          final card = tester.widget<Material>(
            find.byKey(ValueKey('notification-card-$key')),
          );
          final shape = card.shape! as RoundedRectangleBorder;
          expect(shape.borderRadius, BorderRadius.circular(18));
          expect(
            shape.side.color,
            dark ? const Color(0xFF494949) : AppTheme.line,
          );
          expect(card.color, dark ? const Color(0xFF2C2C2C) : Colors.white);
        }
        expect(find.byType(SwitchListTile), findsNWidgets(3));
        for (final tile in tester.widgetList<SwitchListTile>(
          find.byType(SwitchListTile),
        )) {
          // Push is on by default, so the switches can be changed.
          expect(tile.onChanged, isNotNull);
        }
        final system = find.text('System notification settings');
        await tester.ensureVisible(system);
        await tester.pumpAndSettle();
        await tester.tap(system);
        await tester.pumpAndSettle();
        expect(systemSettingsOpened, isTrue);
        expect(
          find.textContaining('unavailable in this version'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
