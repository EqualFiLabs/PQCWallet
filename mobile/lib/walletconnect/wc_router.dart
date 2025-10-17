import 'package:flutter/material.dart';

import 'ui/wc_sessions_screen.dart';

class WcRouter {
  const WcRouter();

  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == WcSessionsScreen.routeName) {
      return MaterialPageRoute<void>(
        builder: (context) => const WcSessionsScreen(),
        settings: settings,
      );
    }
    return null;
  }
}
