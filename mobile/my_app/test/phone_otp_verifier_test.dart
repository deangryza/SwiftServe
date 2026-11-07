import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/presentation/widgets/phone_otp_verifier.dart';
import 'package:my_app/shared/services/api_service.dart';

const _phone = '+639171234567';

Future<void> _pump(
  WidgetTester tester, {
  required List<String> sent,
  required ValueChanged<String> onVerified,
  bool alreadyVerified = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PhoneOtpVerifier(
          phoneNumber: _phone,
          alreadyVerified: alreadyVerified,
          onVerified: onVerified,
          sendCode: (phone) async => sent.add(phone),
          verifyCode: (phone, code) async {
            if (code != '123456') {
              throw const ApiException(
                400,
                '{"code":"OTP_INVALID","message":"That code is incorrect or has expired."}',
              );
            }
            return 'token-for-$phone';
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('sends a code on open and verifies the right code', (
    tester,
  ) async {
    final sent = <String>[];
    String? token;
    await _pump(tester, sent: sent, onVerified: (value) => token = value);
    expect(sent, [_phone]);
    expect(find.textContaining('Resend in 0:'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('phone-otp-input')),
      '000000',
    );
    await tester.pump();
    expect(find.text('That code is incorrect or has expired.'), findsOneWidget);
    expect(token, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('phone-otp-input')),
      '123456',
    );
    await tester.pump();
    expect(token, 'token-for-$_phone');
    expect(find.byKey(const ValueKey('phone-otp-verified')), findsOneWidget);

    // Let the resend countdown finish so no timers are left running.
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('resend is available after the 60 second countdown', (
    tester,
  ) async {
    final sent = <String>[];
    await _pump(tester, sent: sent, onVerified: (_) {});
    await tester.pump(const Duration(seconds: 61));
    expect(find.text("Didn't get code? Resend"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('phone-otp-resend')));
    await tester.pump();
    expect(sent.length, 2);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('an already verified number sends no new SMS', (tester) async {
    final sent = <String>[];
    await _pump(tester, sent: sent, onVerified: (_) {}, alreadyVerified: true);
    expect(sent, isEmpty);
    expect(find.byKey(const ValueKey('phone-otp-verified')), findsOneWidget);
  });
}
