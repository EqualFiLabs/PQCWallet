import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/main.dart';
import 'package:pqc_wallet/utils/address.dart';

void main() {
  testWidgets('WalletMenuDrawer renders options and notifies selection',
      (WidgetTester tester) async {
    WalletAccount? selectedAccount;
    const pqcSample = '0x1234567890abcdef1234567890abcdef12345678';
    const eoaSample = '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: WalletMenuDrawer(
            selectedAccount: WalletAccount.pqcWallet,
            onAccountSelected: (wallet) => selectedAccount = wallet,
            pqcAddress: pqcSample,
            eoaAddress: eoaSample,
          ),
        ),
      ),
    );

    final scaffoldState = tester.firstState<ScaffoldState>(
      find.byType(Scaffold),
    );
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Wallet Menu'), findsOneWidget);
    expect(find.text('PQC Wallet (4337)'), findsOneWidget);
    expect(find.text('EOA (Classic)'), findsOneWidget);
    expect(find.text(truncateAddress(pqcSample)), findsOneWidget);
    expect(find.text(truncateAddress(eoaSample)), findsOneWidget);

    await tester.tap(find.text('EOA (Classic)'));
    await tester.pumpAndSettle();

    expect(selectedAccount, WalletAccount.eoaClassic);
  });
}
