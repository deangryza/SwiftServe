import 'package:flutter/material.dart';

class JobOfferCard extends StatelessWidget {
  final String service;
  final String client;
  final String location;
  final String price;
  final VoidCallback onTap;

  const JobOfferCard({
    super.key,
    required this.service,
    required this.client,
    required this.location,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.work_outline)),
        title: Text(
          service,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('$client\n$location • $price'),
        isThreeLine: true,
        trailing: FilledButton(onPressed: onTap, child: const Text('View')),
      ),
    );
  }
}
