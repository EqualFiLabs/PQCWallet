import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pqc_wallet/ui/components/top_bar.dart';

void main() {
  testWidgets('TopBar lays out long content without overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: TopBar(
            title:
                'EqualFi PQC Wallet – Very Long Account Name That Should Truncate',
            status: TopBarStatus.syncing,
            statusText: 'Syncing pending operations with the bundler...',
            addressText: '0x1234567890abcdef1234567890abcdef12345678',
            onCopy: () {},
            onQr: () {},
            onSettings: () {},
            onOpenMenu: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
