import 'package:flutter/material.dart';

class BudgetScheduleRow extends StatelessWidget {
  final TextEditingController budgetController;
  final TextEditingController scheduleController;

  const BudgetScheduleRow({
    super.key,
    required this.budgetController,
    required this.scheduleController,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: budgetController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Budget",
              hintText: "₱500",
              filled: true,
              fillColor: const Color(0xffF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        const SizedBox(width: 15),

        Expanded(
          child: TextField(
            controller: scheduleController,
            decoration: InputDecoration(
              labelText: "Schedule",
              hintText: "Today, ASAP",
              filled: true,
              fillColor: const Color(0xffF8F8F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}