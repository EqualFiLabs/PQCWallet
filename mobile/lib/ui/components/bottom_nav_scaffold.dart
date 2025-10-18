import 'package:flutter/material.dart';

class NavItem {
  const NavItem({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

class BottomNavScaffold extends StatelessWidget {
  BottomNavScaffold({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.navItems,
    this.type = BottomNavigationBarType.fixed,
  }) : assert(navItems.isNotEmpty, 'Provide at least one navigation item.');

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final List<NavItem> navItems;
  final BottomNavigationBarType type;

  @override
  Widget build(BuildContext context) {
    final safeIndex = currentIndex < 0
        ? 0
        : currentIndex >= navItems.length
            ? navItems.length - 1
            : currentIndex;
    final stackChildren = [
      for (final item in navItems) Builder(builder: item.builder),
    ];

    return Column(
      children: [
        Expanded(
          child: IndexedStack(index: safeIndex, children: stackChildren),
        ),
        SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: safeIndex,
            onTap: onIndexChanged,
            type: type,
            items: [
              for (final item in navItems)
                BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.label,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
