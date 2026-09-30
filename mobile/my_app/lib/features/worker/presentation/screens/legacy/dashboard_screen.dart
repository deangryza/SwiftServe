import 'package:flutter/material.dart';

import '../../widgets/legacy/animated_page.dart';
import '../../widgets/legacy/job_offer_card.dart';
import 'job_details_screen.dart';
import 'notifications_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedPage(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, Zoro!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text('You have 2 new requests in your area.'),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.notifications_none),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              const Text(
                'Ongoing Task',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),

              const Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(Icons.build)),
                  title: Text('Math Tutoring'),
                  subtitle: Text('Shrek • 2:00 PM today'),
                  trailing: Text('Ongoing'),
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'New Job Offer',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),

              JobOfferCard(
                service: 'House Cleaning',
                client: 'Shrek',
                location: 'Makati City',
                price: '₱900',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JobDetailsScreen()),
                  );
                },
              ),

              JobOfferCard(
                service: 'Math Tutoring',
                client: 'Ben C.',
                location: 'Quezon City',
                price: '₱500',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JobDetailsScreen()),
                  );
                },
              ),

              const SizedBox(height: 10),

              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle),
                  title: Text('Completed Jobs'),
                  subtitle: Text('1 completed job'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
