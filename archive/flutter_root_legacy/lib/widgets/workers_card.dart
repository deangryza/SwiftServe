import 'package:flutter/material.dart';


Widget filterChip({
  required String text,
  required bool selected,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: 18,
      vertical: 10,
    ),
    decoration: BoxDecoration(
      color: selected
          ? const Color(0xffEAF2FF)
          : const Color(0xffF3F3F3),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: selected
            ? const Color(0xff2F6FED)
            : Colors.black54,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class WorkerCard extends StatelessWidget {
  final String initials;
  final String name;
  final String job;
  final bool highlight;

  const WorkerCard({
    super.key,
    required this.initials,
    required this.name,
    required this.job,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highlight
              ? const Color(0xff9EC4FF)
              : Colors.grey.shade300,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: highlight
                ? const Color(0xffDCEBFF)
                : const Color(0xffEEF7EE),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 22,
                color: Color(0xff2F6FED),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  "$job •",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),

          TextButton(
            onPressed: () {
              
            },
            child: const Text(
              "Book",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xff2F6FED),
              ),
            ),
          ),
        ],
      ),
    );
  }
}