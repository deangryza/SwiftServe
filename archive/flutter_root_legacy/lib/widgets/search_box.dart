import 'package:flutter/material.dart';

class SearchBox extends StatelessWidget {
  final VoidCallback? onTap;
  final TextEditingController? controller;

  final bool readOnly;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  const SearchBox({
    super.key,
    this.onTap,
    this.controller,
    this.readOnly = false,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,

      decoration: InputDecoration(
        hintText: "Search for a service or worker...",
        hintStyle: TextStyle(
          color: Colors.grey.shade500,
        ),

        prefixIcon: const Icon(
          Icons.search,
          color: Colors.grey,
        ),

        suffixIcon: controller != null &&
                controller!.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller!.clear();
                  onChanged?.call("");
                },
              )
            : null,

        filled: true,
        fillColor: const Color(0xffF5F5F5),

        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
