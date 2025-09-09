import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_wallet/services/rpc.dart';

void main() {
  test('callViewHex performs eth_call and returns hex result', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    server.listen((HttpRequest request) async {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['method'], 'eth_call');
      final response = jsonEncode({
        'jsonrpc': '2.0',
        'id': json['id'],
        'result': '0xdeadbeef'
      });
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(response);
      await request.response.close();
    });

    final client = RpcClient('http://${server.address.host}:${server.port}');
    final res = await client.callViewHex('0xabc', '0x123');
    expect(res, '0xdeadbeef');
  });
}
