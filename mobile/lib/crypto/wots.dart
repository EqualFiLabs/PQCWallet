import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class Wots {
  static const int w = 16;
  static const int L1 = 64; // 256 bits / log2(16)
  static const int L2 = 3;  // ceil(log_16(960)) = 3
  static const int L = L1 + L2; // 67
  static const int n = 32; // bytes per element

  static List<int> _F(List<int> x) => sha256.convert(x).bytes;

  static List<int> _toNibbles(Uint8List h) {
    final out = List<int>.filled(64, 0);
    for (int i = 0; i < 32; i++) {
      final b = h[i];
      out[2*i]   = (b >> 4) & 0x0f;
      out[2*i+1] = b & 0x0f;
    }
    return out;
  }

  static List<int> _digitsWithChecksum(Uint8List msgHash) {
    final d = List<int>.filled(L, 0);
    final nibbles = _toNibbles(msgHash);
    for (int i = 0; i < L1; i++) { d[i] = nibbles[i]; }
    int csum = 0;
    for (int i = 0; i < L1; i++) csum += (w - 1) - d[i];
    d[L1]   = (csum >> 8) & 0x0f;
    d[L1+1] = (csum >> 4) & 0x0f;
    d[L1+2] = csum & 0x0f;
    return d;
    }

  /// Deterministic keygen from 32-byte seed.
  static (List<Uint8List> sk, List<Uint8List> pk) keygen(Uint8List seed) {
    final sk = <Uint8List>[];
    final pk = <Uint8List>[];
    for (int i = 0; i < L; i++) {
      final s = sha256.convert([...seed, i, 0, 0, 0]).bytes; // simple expand
      Uint8List v = Uint8List.fromList(s);
      for (int j = 0; j < w - 1; j++) { v = Uint8List.fromList(_F(v)); }
      sk.add(Uint8List.fromList(s));
      pk.add(v);
    }
    return (sk, pk);
  }

  static List<Uint8List> sign(Uint8List msgHash, List<Uint8List> sk) {
    final d = _digitsWithChecksum(msgHash);
    final sig = <Uint8List>[];
    for (int i = 0; i < L; i++) {
      Uint8List v = sk[i];
      for (int j = 0; j < d[i]; j++) { v = Uint8List.fromList(_F(v)); }
      sig.add(v);
    }
    return sig;
  }

  static Uint8List commitPk(List<Uint8List> pk) {
    final concat = <int>[];
    for (final p in pk) { concat.addAll(p); }
    return Uint8List.fromList(sha256.convert(concat).bytes);
  }
}
