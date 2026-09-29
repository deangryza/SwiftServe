import 'package:flutter/material.dart';
import '../widgets/workers_card.dart';

class WorkersFoundScreen extends StatelessWidget {
  const WorkersFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          "Workers found",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 15),
            child: Icon(
              Icons.more_horiz,
              color: Colors.black,
            ),
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text(
              'For: "Math tutor" · sorted by match',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 20),

            const Divider(),

            const SizedBox(height: 15),

            Row(
              children: [

                filterChip(
                  text: "Nearest first",
                  selected: true,
                ),

                const SizedBox(width: 10),

                filterChip(
                  text: "Top rated",
                  selected: false,
                ),

              ],
            ),

            const SizedBox(height: 25),

            const Text(
              "Best match",
              style: TextStyle(
                color: Color(0xff2F6FED),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),

            const SizedBox(height: 15),

            Expanded(
              child: ListView(
                children: const [

                  WorkerCard(
                    initials: "ZR",
                    name: "Zoro R.",
                    job: "Tutoring",
                    highlight: true,
                  ),

                  SizedBox(height: 18),

                  WorkerCard(
                    initials: "BC",
                    name: "Ben C.",
                    job: "Academic help",
                  ),

                  SizedBox(height: 18),

                  WorkerCard(
                    initials: "LT",
                    name: "Lea T.",
                    job: "Tutoring",
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}