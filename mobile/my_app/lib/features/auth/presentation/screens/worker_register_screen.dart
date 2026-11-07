import 'package:flutter/material.dart';

import 'client_register_screen.dart';
import '../widgets/phone_otp_verifier.dart';
import '../widgets/registration_contact_fields.dart';

class WorkerRegisterScreen extends StatelessWidget {
  const WorkerRegisterScreen({
    super.key,
    this.contactAvailability,
    this.otpSender,
    this.otpVerifier,
  });
  final ContactAvailabilityLookup? contactAvailability;
  final SendPhoneOtp? otpSender;
  final VerifyPhoneOtp? otpVerifier;

  @override
  Widget build(BuildContext context) => AccountRegistrationScreen(
    role: 'worker',
    contactAvailability: contactAvailability,
    otpSender: otpSender,
    otpVerifier: otpVerifier,
  );
}
