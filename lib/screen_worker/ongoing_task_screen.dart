import 'package:flutter/material.dart';

import '../widgets_worker/animated_page.dart';
import '../widgets_worker/task_status_card.dart';

class OngoingTaskScreen extends StatelessWidget {
  const OngoingTaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Ongoing Task')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const TaskStatusCard(),

            const SizedBox(height: 15),

            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Message Client'),
            ),

            const SizedBox(height: 10),

            OutlinedButton(
              onPressed: () {},
              child: const Text('Mark as Completed'),
            ),
          ],
        ),
      ),
    );
  }
}
