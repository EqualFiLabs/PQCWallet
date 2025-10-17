import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

class WcSigner {
  const WcSigner({
    required Credentials credentials,
  }) : _credentials = credentials;

  final Credentials _credentials;

  Credentials get credentials => _credentials;

  Future<Uint8List> sign(Uint8List payload) async {
    return Future<Uint8List>.value(payload);
  }
}
