import 'dart:io';
import 'package:flutter/material.dart';

class PreviewCard extends StatelessWidget {
  final File? image;

  const PreviewCard({
    super.key,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "Preview",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: image == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      Icon(
                        Icons.image_outlined,
                        size: 60,
                        color: Colors.grey.shade500,
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        "No Preview Available",
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      image!,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),

        ],
      ),
    );
  }
}