import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.onEdit,
    this.name = 'Worker',
    this.verified = false,
    this.verificationLabel,
  });

  final VoidCallback onEdit;
  final String name;
  final bool verified;
  final String? verificationLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 42,
              child: Text(
                name.isEmpty ? 'W' : name.substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              verificationLabel ??
                  (verified ? 'Verified' : 'Verification pending'),
              style: TextStyle(color: verified ? Colors.green : Colors.orange),
            ),
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ProfileStat(value: '-', label: 'Jobs'),
                _ProfileStat(value: '-', label: 'Rating'),
                _ProfileStat(value: '-', label: 'Years'),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onEdit,
              child: const Text('Edit Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      Text(label),
    ],
  );
}
