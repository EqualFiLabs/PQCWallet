import 'package:flutter/material.dart';

class WcSessionsScreen extends StatelessWidget {
  const WcSessionsScreen({super.key});

  static const String routeName = '/walletconnect/sessions';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('WalletConnect Sessions'),
      ),
    );
  }
}
