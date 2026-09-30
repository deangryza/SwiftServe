import 'package:flutter/material.dart';

class ReviewTags extends StatefulWidget {
  const ReviewTags({super.key});

  @override
  State<ReviewTags> createState() => _ReviewTagsState();
}

class _ReviewTagsState extends State<ReviewTags> {
  final List<String> tags = [
    "On Time",
    "Friendly",
    "Patient",
    "Professional",
    "Skilled",
    "Would Hire Again",
  ];

  final List<String> selectedTags = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "What did you like?",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),

        const SizedBox(height: 15),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: tags.map((tag) {
            final isSelected = selectedTags.contains(tag);

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    selectedTags.remove(tag);
                  } else {
                    selectedTags.add(tag);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xff2F6FED)
                      : const Color(0xffF5F5F5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xff2F6FED)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
