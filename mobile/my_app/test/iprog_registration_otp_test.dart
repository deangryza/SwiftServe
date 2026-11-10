import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/data/iprog_registration_otp.dart';
import 'package:my_app/features/auth/presentation/widgets/registration_otp_screen.dart';

const _phone = '+639171234567';

IprogRegistrationOtp _gateway({required bool skipped}) => IprogRegistrationOtp(
  send: (_) async => skipped,
  verify: (_, _) async => 'signed-token',
);

Future<int Function()> _pumpOtpScreen(
  WidgetTester tester,
  IprogRegistrationOtp gateway,
) async {
  var verified = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: RegistrationOtpScreen(
        phone: _phone,
        gateway: gateway,
        verifyButtonKey: const ValueKey('verify'),
        onVerified: () => verified++,
        onEditPhone: () {},
        onBack: () {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return () => verified;
}

void main() {
  testWidgets('server SMS switch passes through the code screen once', (
    tester,
  ) async {
    final gateway = _gateway(skipped: true);
    final verified = await _pumpOtpScreen(tester, gateway);

    expect(verified(), 1);
    expect(gateway.verifiedFor(_phone), isTrue);
    expect(gateway.tokenFor(_phone), isNull);
    expect(gateway.verifiedFor('+639170000000'), isFalse);
  });

  testWidgets('a normal send still waits for the code', (tester) async {
    final gateway = _gateway(skipped: false);
    final verified = await _pumpOtpScreen(tester, gateway);

    expect(verified(), 0);
    expect(gateway.verifiedFor(_phone), isFalse);

    await gateway.verify(_phone, '123456');
    expect(gateway.tokenFor(_phone), 'signed-token');
    await tester.pumpWidget(const SizedBox());
  });
}
