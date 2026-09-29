import 'package:flutter/material.dart';

import '../widgets/worker_booking_card.dart';
import '../widgets/message_worker_button.dart';
import '../widgets/cancel_request_button.dart';

class BookingRequestScreen extends StatelessWidget {
  const BookingRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                children: [

                  IconButton(
                    onPressed: (){
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.arrow_back_ios_new),
                  ),

                  const SizedBox(width: 6),

                  const Text(
                    "Booking request",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                ],
              ),

              const Divider(),

              const SizedBox(height: 40),

              const Center(
                child: Text(
                  "Book sent to Zoro R.",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Center(
                child: Text(
                  "Waiting for worker to accept...",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),

              const SizedBox(height: 35),

              const WorkerBookingCard(),

              const SizedBox(height: 30),

              const MessageWorkerButton(),

              const SizedBox(height: 15),

              const CancelRequestButton(),

              const SizedBox(height: 25),

              Center(
                child: Text(
                  "Average response time: 2 min",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 15,
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}