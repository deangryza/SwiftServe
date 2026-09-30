import 'package:flutter/material.dart';

class SubmitReviewButton extends StatelessWidget {
  const SubmitReviewButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: () {
          // TODO: Submit Review
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff2F6FED),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: const Text(
          "Submit Review",
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
