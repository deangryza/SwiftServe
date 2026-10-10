import 'package:flutter/material.dart';

import 'client_register_screen.dart';

class WorkerRegisterScreen extends StatelessWidget {
  const WorkerRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AccountRegistrationScreen(role: 'worker');
}
