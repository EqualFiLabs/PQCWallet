import 'dart:convert';
import 'package:http/http.dart' as http;

class RpcClient {
  final String url;
  RpcClient(this.url);

  Future<dynamic> call(String method, [dynamic params]) async {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': DateTime.now().millisecondsSinceEpoch,
      'method': method,
      'params': params ?? [],
    });
    final res = await http.post(Uri.parse(url),
        headers: {'Content-Type': 'application/json'}, body: body);
    if (res.statusCode != 200) {
      throw Exception('RPC ${res.statusCode}: ${res.body}');
    }
    final json = jsonDecode(res.body);
    if (json['error'] != null) {
      throw Exception('RPC error: ${json['error']}');
    }
    return json['result'];
  }
}

extension RpcView on RpcClient {
  /// Calls a contract view function with `to` and `data` (hex string with 0x).
  Future<String> callViewHex(String to, String dataHex) async {
    final payload = {'to': to, 'data': dataHex};
    final res = await call('eth_call', [payload, 'latest']);
    // Result is a hex string (0x...)
    return res.toString();
  }

  /// Suggests a priority fee per gas in wei.
  Future<BigInt> maxPriorityFeePerGas() async {
    final hex = await call('eth_maxPriorityFeePerGas', []);
    return BigInt.parse(hex.toString().substring(2), radix: 16);
  }

  /// Returns fee history for recent blocks.
  Future<Map<String, dynamic>> feeHistory(
      int blockCount, List<int> rewardPercentiles) async {
    final res = await call('eth_feeHistory', [
      '0x${blockCount.toRadixString(16)}',
      'latest',
      rewardPercentiles.map((p) => p.toDouble()).toList()
    ]);
    return Map<String, dynamic>.from(res as Map);
  }
}
