import 'package:flutter/material.dart';

import '../../data/iprog_registration_otp.dart';
import 'client_register_screen.dart';
import '../widgets/registration_contact_fields.dart';

class WorkerRegisterScreen extends StatelessWidget {
  const WorkerRegisterScreen({
    super.key,
    this.contactAvailability,
    this.smsGateway,
  });
  final ContactAvailabilityLookup? contactAvailability;
  final IprogRegistrationOtp? smsGateway;

  @override
  Widget build(BuildContext context) => AccountRegistrationScreen(
    role: 'worker',
    contactAvailability: contactAvailability,
    smsGateway: smsGateway,
  );
}
