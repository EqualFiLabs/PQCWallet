import 'dart:convert';
import 'package:http/http.dart' as http;

class BundlerClient {
  final String url;
  BundlerClient(this.url);

  Future<Map<String, dynamic>> estimateUserOpGas(Map<String, dynamic> userOp, String entryPoint) async {
    final body = _rpc('eth_estimateUserOperationGas', [userOp, entryPoint]);
    final res = await http.post(Uri.parse(url), headers: _h(), body: body);
    _check(res);
    return (jsonDecode(res.body)['result'] as Map).cast<String, dynamic>();
  }

  Future<String> sendUserOperation(Map<String, dynamic> userOp, String entryPoint) async {
    final body = _rpc('eth_sendUserOperation', [userOp, entryPoint]);
    final res = await http.post(Uri.parse(url), headers: _h(), body: body);
    _check(res);
    return (jsonDecode(res.body)['result'] as String);
  }

  Future<Map<String, dynamic>?> getUserOperationReceipt(String userOpHash) async {
    final body = _rpc('eth_getUserOperationReceipt', [userOpHash]);
    final res = await http.post(Uri.parse(url), headers: _h(), body: body);
    final json = jsonDecode(res.body);
    if (json['error'] != null) throw Exception('Bundler error: ${json['error']}');
    return json['result'] as Map<String, dynamic>?;
  }

  String _rpc(String method, List<dynamic> params) => jsonEncode({
        'jsonrpc': '2.0',
        'id': DateTime.now().millisecondsSinceEpoch,
        'method': method,
        'params': params,
      });

  Map<String, String> _h() => {'Content-Type': 'application/json'};

  void _check(http.Response r) {
    if (r.statusCode != 200) {
      throw Exception('Bundler HTTP ${r.statusCode}: ${r.body}');
    }
  }
}
