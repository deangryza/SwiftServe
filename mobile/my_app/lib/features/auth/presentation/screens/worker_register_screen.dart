import 'package:flutter/material.dart';

import 'client_register_screen.dart';
import '../widgets/registration_contact_fields.dart';

class WorkerRegisterScreen extends StatelessWidget {
  const WorkerRegisterScreen({super.key, this.contactAvailability});
  final ContactAvailabilityLookup? contactAvailability;

  @override
  Widget build(BuildContext context) => AccountRegistrationScreen(
    role: 'worker',
    contactAvailability: contactAvailability,
  );
}
