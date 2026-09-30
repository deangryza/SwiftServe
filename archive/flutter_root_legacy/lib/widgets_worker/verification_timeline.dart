import 'package:flutter/material.dart';

class VerificationTimeline extends StatelessWidget {
  const VerificationTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _item('Identity Check', 'Submitted', true),
        _item('Certificates', 'Submitted', true),
        _item('Portfolio / Proof of Work', 'Under review', false),
      ],
    );
  }

  Widget _item(String title, String status, bool done) {
    return Card(
      child: ListTile(
        leading: Icon(done ? Icons.check_circle : Icons.hourglass_top),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Text(status),
      ),
    );
  }
}
