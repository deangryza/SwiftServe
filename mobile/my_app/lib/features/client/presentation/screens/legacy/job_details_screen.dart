import 'package:flutter/material.dart';

import '../../widgets/legacy/action_buttons_row.dart';
import '../../widgets/legacy/job_action_button.dart';
import '../../widgets/legacy/job_details_card.dart';
import '../../widgets/legacy/service_progress_card.dart';
import '../../widgets/legacy/tracking_status_card.dart';
import '../../widgets/legacy/worker_info_card.dart';

class JobDetailsScreen extends StatelessWidget {
  const JobDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F8FC),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        title: const Text(
          "Job Details",
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.black,
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            /// Worker Information + Map
            WorkerInfoCard(),

            SizedBox(height: 18),

            /// ETA Card
            TrackingStatusCard(),

            SizedBox(height: 18),

            /// Progress
            ServiceProgressCard(),

            SizedBox(height: 18),

            /// Job Details
            JobDetailsCard(),

            SizedBox(height: 20),

            /// Call & Message
            ActionButtonsRow(),

            SizedBox(height: 20),

            /// Track Worker Button
            JobActionButton(text: "Track Worker"),

            SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
