import 'package:flutter/material.dart';

class HistoryJobCard extends StatelessWidget {
  final String service;
  final String date;
  final String amount;

  const HistoryJobCard({
    super.key,
    required this.service,
    required this.date,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.check)),
        title: Text(service),
        subtitle: Text('Completed • $date'),
        trailing: Text(amount),
      ),
    );
  }
}
