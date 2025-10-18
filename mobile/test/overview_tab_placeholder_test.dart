import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/ui/overview_tab_placeholder.dart';

void main() {
  testWidgets(
    'OverviewTabPlaceholder explains where to find wallet actions',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OverviewTabPlaceholder(),
          ),
        ),
      );

      expect(find.text('Overview placeholder'), findsOneWidget);
      expect(
        find.text(
          'Overview is moving. Open the Wallet tab for balance and actions.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.space_dashboard_outlined), findsOneWidget);
    },
  );
}
