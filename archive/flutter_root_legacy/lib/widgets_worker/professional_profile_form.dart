import 'package:flutter/material.dart';

class ProfessionalProfileForm extends StatelessWidget {
  final String category;
  final String experience;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onExperience;
  final TextEditingController skills;

  const ProfessionalProfileForm({
    super.key,
    required this.category,
    required this.experience,
    required this.onCategory,
    required this.onExperience,
    required this.skills,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Service Category',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),

        const SizedBox(height: 7),

        DropdownButtonFormField<String>(
          value: category,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items:
              [
                'Select service',
                'Plumber',
                'Electrician',
                'House Cleaning',
                'Tutor',
                'Aircon Repair',
                'Carpenter',
                'Painter',
                'Others',
              ].map((item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              }).toList(),
          onChanged: onCategory,
        ),

        const SizedBox(height: 16),

        const Text(
          'Primary Skills',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),

        const SizedBox(height: 7),

        TextField(
          controller: skills,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. Wiring, troubleshooting, installation',
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          'Experience Level',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),

        const SizedBox(height: 7),

        DropdownButtonFormField<String>(
          value: experience,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items:
              [
                'Select experience',
                'Beginner',
                'Intermediate',
                'Experienced',
                'Expert',
              ].map((item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              }).toList(),
          onChanged: onExperience,
        ),
      ],
    );
  }
}
