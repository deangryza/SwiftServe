import 'package:flutter/material.dart';

class ProfileAboutField extends StatelessWidget {
  const ProfileAboutField({
    super.key,
    required this.controller,
    required this.textColor,
    required this.mutedColor,
    this.enabled = true,
  });

  final TextEditingController controller;
  final Color textColor;
  final Color mutedColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    minLines: 3,
    maxLines: 5,
    maxLength: 500,
    keyboardType: TextInputType.multiline,
    textCapitalization: TextCapitalization.sentences,
    style: TextStyle(color: textColor),
    decoration: InputDecoration(
      labelText: 'About',
      alignLabelWithHint: true,
      hintText: 'Write a short description about yourself',
      helperText: 'Visible to other users on your profile.',
      helperMaxLines: 2,
      labelStyle: TextStyle(color: mutedColor),
      prefixIcon: Icon(Icons.info_outline, color: mutedColor),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: mutedColor.withValues(alpha: 0.45)),
      ),
    ),
  );
}
