import 'package:flutter/material.dart';

/// Registration errors must stay red even though the main app uses muted ink.
class RegistrationValidationTheme extends StatelessWidget {
  const RegistrationValidationTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const error = Color(0xFFC62828);
    OutlineInputBorder border(double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: error, width: width),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(error: error),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          errorBorder: border(1.5),
          focusedErrorBorder: border(2),
          errorStyle: const TextStyle(color: error),
        ),
      ),
      child: child,
    );
  }
}
