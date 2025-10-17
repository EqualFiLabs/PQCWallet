import 'package:reown_walletkit/reown_walletkit.dart';

class WcClient {
  const WcClient({
    required ReownWalletKit walletKit,
  }) : _walletKit = walletKit;

  final ReownWalletKit _walletKit;

  ReownWalletKit get walletKit => _walletKit;

  Future<void> initialize() async {
    await Future<void>.value();
  }
}
