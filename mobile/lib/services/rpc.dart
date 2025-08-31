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
    final res = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: body);
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
