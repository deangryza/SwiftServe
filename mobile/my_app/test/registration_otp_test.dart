import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/domain/registration_otp_gateway.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_otp_screen.dart';
import 'package:my_app/shared/theme/app_theme.dart';

class TestOtpGateway extends RegistrationOtpGateway {
  int sends = 0, verifies = 0, invalidations = 0;
  bool verified = false, failSend = false, failVerify = false, confirm = true;
  Completer<void>? pendingVerify;
  String? sentPhone, checkedCode;
  @override
  bool verifiedFor(String phone) => verified && phone == sentPhone;
  @override
  Future<void> send(String phone, {bool resend = false}) async {
    sends++;
    sentPhone = phone;
    verified = false;
    if (failSend) {
      throw const RegistrationOtpException('Could not send SMS. Retry.');
    }
  }

  @override
  Future<void> verify(String phone, String code) async {
    verifies++;
    checkedCode = code;
    await pendingVerify?.future;
    if (failVerify) {
      throw const RegistrationOtpException('Incorrect code. Try again.');
    }
    verified = confirm && phone == sentPhone && code == '123456';
    notifyListeners();
  }

  @override
  void invalidate() {
    invalidations++;
    verified = false;
  }
}

void main() {
  const phone = '+639175253171';
  const buttonKey = ValueKey('otp-verify');
  Future<void> pump(
    WidgetTester tester,
    TestOtpGateway gateway, {
    VoidCallback? onVerified,
    VoidCallback? edit,
    DateTime Function()? now,
    TextScaler scaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), textScaler: scaler),
          child: RegistrationOtpScreen(
            phone: phone,
            gateway: gateway,
            verifyButtonKey: buttonKey,
            onVerified: onVerified ?? () {},
            onEditPhone: edit ?? () {},
            onBack: () {},
            now: now ?? DateTime.now,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'reference layout uses six cells, real code entry, clear and no email fallback',
    (tester) async {
      final gateway = TestOtpGateway();
      await pump(tester, gateway);
      expect(find.text('Enter One-Time-Password'), findsOneWidget);
      expect(find.textContaining('Login via email'), findsNothing);
      expect(gateway.sends, 1);
      final input = find.byKey(const ValueKey('registration-otp-input'));
      await tester.enterText(input, '12a34567');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, '123456');
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      expect(
        tester.widget<FilledButton>(find.byKey(buttonKey)).onPressed,
        isNull,
      );
      expect(gateway.sends, 1);
    },
  );
  testWidgets(
    'edit number invalidates old proof and returns to contact fields callback',
    (tester) async {
      final gateway = TestOtpGateway();
      var edits = 0;
      await pump(tester, gateway, edit: () => edits++);
      await tester.tap(find.text('Edit mobile number'));
      await tester.pump();
      expect(edits, 1);
      expect(gateway.invalidations, 1);
    },
  );
  testWidgets(
    'verify requires six digits and confirmed gateway result, exactly once',
    (tester) async {
      final gateway = TestOtpGateway()..pendingVerify = Completer<void>();
      var completions = 0;
      await pump(tester, gateway, onVerified: () => completions++);
      final input = find.byKey(const ValueKey('registration-otp-input'));
      await tester.enterText(input, '12345');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(buttonKey)).onPressed,
        isNull,
      );
      await tester.enterText(input, '123456');
      await tester.pump();
      await tester.tap(find.byKey(buttonKey));
      await tester.pump();
      expect(gateway.verifies, 1);
      expect(completions, 0);
      expect(
        tester.widget<FilledButton>(find.byKey(buttonKey)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Edit mobile number'),
            )
            .onPressed,
        isNull,
      );
      gateway.pendingVerify!.complete();
      await tester.pump();
      await tester.pump();
      expect(completions, 1);
      expect(gateway.checkedCode, '123456');
    },
  );
  testWidgets(
    'wrong codes and unconfirmed results remain on OTP screen for retry',
    (tester) async {
      final gateway = TestOtpGateway()..failVerify = true;
      var completed = false;
      await pump(tester, gateway, onVerified: () => completed = true);
      await tester.enterText(
        find.byKey(const ValueKey('registration-otp-input')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.byKey(buttonKey));
      await tester.pump();
      expect(find.text('Incorrect code. Try again.'), findsOneWidget);
      expect(completed, isFalse);
      gateway.failVerify = false;
      gateway.confirm = false;
      await tester.tap(find.byKey(buttonKey));
      await tester.pump();
      expect(
        find.text('Verification was not confirmed. Please retry.'),
        findsOneWidget,
      );
      expect(completed, isFalse);
      gateway.confirm = true;
      await tester.tap(find.byKey(buttonKey));
      await tester.pump();
      expect(completed, isTrue);
    },
  );
  testWidgets('resend has a real three-minute deadline and resets the code', (
    tester,
  ) async {
    final gateway = TestOtpGateway();
    var now = DateTime(2026, 11, 6, 10);
    await pump(tester, gateway, now: () => now);
    expect(find.text('Resend code in 3 minutes 0 seconds'), findsOneWidget);
    expect(find.text('Resend code'), findsNothing);
    now = now.add(const Duration(seconds: 179));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('0 minutes 1 seconds'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(
      find.byKey(const ValueKey('registration-otp-input')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.text('Resend code'));
    await tester.pump();
    await tester.pump();
    expect(gateway.sends, 2);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('registration-otp-input')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets(
    'send failure is retryable and never claims that a code was sent',
    (tester) async {
      final gateway = TestOtpGateway()..failSend = true;
      await pump(tester, gateway);
      expect(find.text('Could not send SMS. Retry.'), findsOneWidget);
      expect(find.textContaining('OTP) sent to'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(buttonKey)).onPressed,
        isNull,
      );
      gateway.failSend = false;
      await tester.tap(find.text('Send code'));
      await tester.pump();
      await tester.pump();
      expect(gateway.sends, 2);
      expect(find.text('Could not send SMS. Retry.'), findsNothing);
    },
  );
  testWidgets('disabled mode does not send SMS or claim verification', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationOtpScreen(
          phone: phone,
          onVerified: () {},
          onEditPhone: () {},
          onBack: () {},
          verifyButtonKey: buttonKey,
        ),
      ),
    );
    expect(
      find.textContaining('Continuing does not verify your phone number.'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Verify'), findsNothing);
  });
  for (final scale in [1.0, 1.7]) {
    testWidgets('OTP fits a narrow mobile screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = TestOtpGateway();
      await pump(tester, gateway, scaler: TextScaler.linear(scale));
      expect(tester.takeException(), isNull);
      expect(find.text('Edit mobile number'), findsOneWidget);
    });
  }
}
