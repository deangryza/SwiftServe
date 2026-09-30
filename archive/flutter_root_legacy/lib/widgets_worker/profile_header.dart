import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  final VoidCallback onEdit;

  const ProfileHeader({super.key, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 42,
              child: Text('ZR', style: TextStyle(fontSize: 24)),
            ),

            const SizedBox(height: 10),

            const Text(
              'Zoro R.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),

            const Text('✓ Verified', style: TextStyle(color: Colors.green)),

            const SizedBox(height: 14),

            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ProfileStat(value: '12', label: 'Jobs'),
                _ProfileStat(value: '4.9', label: 'Rating'),
                _ProfileStat(value: '8+', label: 'Years'),
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
  final String value;
  final String label;

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        Text(label),
      ],
    );
  }
}
