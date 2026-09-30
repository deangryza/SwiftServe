import 'package:flutter/material.dart';

class ConversationTile extends StatelessWidget {
  final String name;
  final String preview;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.name,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Text('MS')),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(preview),
        onTap: onTap,
      ),
    );
  }
}
