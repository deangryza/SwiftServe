import 'package:flutter/material.dart';

class CommentBox extends StatefulWidget {
  const CommentBox({super.key});

  @override
  State<CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends State<CommentBox> {
  final TextEditingController controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Leave a comment",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: "Tell us about your experience with this worker...",
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
            filled: true,
            fillColor: const Color(0xffFAFAFA),
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xffE5E5E5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xff2F6FED),
                width: 1.5,
              ),
            ),
          ),
          onChanged: (_) {
            setState(() {});
          },
        ),

        const SizedBox(height: 8),

        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "${controller.text.length}/250",
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
