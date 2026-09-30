import 'package:flutter/material.dart';

class RecentSearchTile extends StatelessWidget {
  final String title;

  const RecentSearchTile({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,

      leading: const Icon(Icons.history, color: Colors.grey),

      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),

      trailing: const Icon(Icons.north_east, color: Colors.grey),
    );
  }
}
