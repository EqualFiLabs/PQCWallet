import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class WOTSSeedService {
  const WOTSSeedService();

  Uint8List deriveMaster(Uint8List ecdsaPrivateKey) {
    return _hkdfSha256(ecdsaPrivateKey, utf8.encode('WOTS'), 32);
  }

  Uint8List _hkdfSha256(Uint8List ikm, List<int> info, int len) {
    final prk = Hmac(sha256, List.filled(32, 0)).convert(ikm).bytes;
    var out = <int>[];
    var t = <int>[];
    var i = 1;
    while (out.length < len) {
      final h = Hmac(sha256, prk).convert([...t, ...info, i]).bytes;
      out.addAll(h);
      t = h;
      i++;
    }
    return Uint8List.fromList(out.sublist(0, len));
  }
}
