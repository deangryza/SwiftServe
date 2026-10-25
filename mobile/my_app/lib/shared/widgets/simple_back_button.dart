import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A quiet, consistent back control for white page headers.
class SimpleBackButton extends StatelessWidget {
  const SimpleBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48,
    child: IconButton(
      onPressed: onPressed,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: Colors.transparent,
        side: const BorderSide(color: AppTheme.yellow, width: 0.8),
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.arrow_back, size: 20),
    ),
  );
}
