import 'package:flutter/material.dart';

import 'navigation_placeholder_screen.dart';

/// Placeholder for the Overview tab while content lives elsewhere.
class OverviewTabPlaceholder extends StatelessWidget {
  const OverviewTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const NavigationPlaceholderScreen(
      icon: Icons.space_dashboard_outlined,
      title: 'Overview placeholder',
      message:
          'Overview is moving. Open the Wallet tab for balance and actions.',
    );
  }
}
