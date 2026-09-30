import 'package:flutter/material.dart';

class AcceptedBookingCard extends StatelessWidget {
  const AcceptedBookingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.check_circle, size: 70),

            SizedBox(height: 12),

            Text(
              'Booking Accepted!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),

            SizedBox(height: 6),

            Text(
              'You can now coordinate with the client.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
