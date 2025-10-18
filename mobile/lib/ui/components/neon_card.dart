import 'package:flutter/material.dart';

/// Reusable gradient card used across settings, placeholders, etc.
class NeonCard extends StatelessWidget {
  const NeonCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.25),
            theme.colorScheme.secondary.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.40),
          width: 1.5,
        ),
      ),
      padding: padding ?? const EdgeInsets.all(12),
      child: child,
    );
  }
}
