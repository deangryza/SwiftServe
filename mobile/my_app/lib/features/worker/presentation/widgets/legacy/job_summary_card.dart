import 'package:flutter/material.dart';

class JobSummaryCard extends StatelessWidget {
  final String service;
  final String client;
  final String location;
  final String schedule;
  final String price;

  const JobSummaryCard({
    super.key,
    required this.service,
    required this.client,
    required this.location,
    required this.schedule,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(Icons.work_outline, 'Service', service),
        _row(Icons.person_outline, 'Client', client),
        _row(Icons.location_on_outlined, 'Location', location),
        _row(Icons.schedule, 'Schedule', schedule),
        _row(Icons.payments_outlined, 'Offer', price),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
