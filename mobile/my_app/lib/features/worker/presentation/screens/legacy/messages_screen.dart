import 'package:flutter/material.dart';

import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/conversation_tile.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Messages',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 12),

              const TextField(
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              ConversationTile(
                name: 'Shrek',
                preview: 'Salamat po sa help',
                onTap: () {},
              ),

              ConversationTile(
                name: 'Ben C.',
                preview: 'Salamat po sa tutor',
                onTap: () {},
              ),

              ConversationTile(
                name: 'Lea T.',
                preview: 'Tutoring schedule?',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
