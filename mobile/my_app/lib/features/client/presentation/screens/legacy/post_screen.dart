import 'package:flutter/material.dart';
import '../../widgets/legacy/post_button.dart';
import '../../widgets/legacy/post_custom_text_field.dart';
import '../../widgets/legacy/category_dropdown.dart';
import '../../widgets/legacy/budget_schedule_row.dart';
import '../../widgets/legacy/post_location_card.dart';

class PostScreen extends StatefulWidget {
  const PostScreen({super.key});

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  String selectedAddress = "Tap to choose location";

  final TextEditingController jobTitleController = TextEditingController();

  final TextEditingController budgetController = TextEditingController();

  final TextEditingController scheduleController = TextEditingController();

  final TextEditingController descriptionController = TextEditingController();

  String? selectedCategory;

  @override
  void dispose() {
    jobTitleController.dispose();
    budgetController.dispose();
    scheduleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Header
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    "Post Need",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const Spacer(),

                  ElevatedButton(
                    onPressed: () {},

                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),

                    child: const Text("Post"),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              /// Job Title
              PostCustomTextField(
                label: "Job Title",
                hintText: "e.g. Need Math Tutor",
                controller: jobTitleController,
              ),

              const SizedBox(height: 20),

              /// Category
              CategoryDropdown(
                value: selectedCategory,
                onChanged: (value) {
                  setState(() {
                    selectedCategory = value;
                  });
                },
              ),

              const SizedBox(height: 20),

              /// Budget & Schedule
              BudgetScheduleRow(
                budgetController: budgetController,
                scheduleController: scheduleController,
              ),

              const SizedBox(height: 20),

              /// Location
              PostLocationCard(
                address: selectedAddress,
                onTap: () {
                  // Google Maps mamaya
                },
              ),

              const SizedBox(height: 20),

              /// Description
              PostCustomTextField(
                label: "Description",
                hintText: "Describe your job request...",
                controller: descriptionController,
                maxLines: 5,
              ),
              PostButton(
                onPressed: () {
                  //dito po natin lalagay firebase ehe
                },
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
