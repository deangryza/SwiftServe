import 'package:flutter/material.dart';

class TaskStatusCard extends StatelessWidget {
  const TaskStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Shrek'),
            subtitle: Text('House Cleaning'),
          ),
        ),

        const Card(
          child: ListTile(
            leading: Icon(Icons.location_on_outlined),
            title: Text('Client Location'),
            subtitle: Text('Makati City'),
          ),
        ),

        const Card(
          child: ListTile(
            leading: Icon(Icons.schedule),
            title: Text('Schedule'),
            subtitle: Text('Today • 2:00 PM'),
          ),
        ),
      ],
    );
  }
}
