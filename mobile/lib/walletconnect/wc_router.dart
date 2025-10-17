import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:reown_walletkit/reown_walletkit.dart';

import 'ui/wc_sessions_screen.dart';
import 'wc_signer.dart';

class WcRouter {
  const WcRouter();

  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == WcSessionsScreen.routeName) {
      return MaterialPageRoute<void>(
        builder: (context) => const WcSessionsScreen(),
        settings: settings,
      );
    }
    return null;
  }

  Future<JsonRpcResponse<Object?>> dispatch({
    required SessionRequestEvent event,
    required SessionData session,
    required Map<int, WcSigner> signers,
  }) async {
    try {
      final chainId = _parseChainId(event.chainId);
      final signer = signers[chainId];
      if (signer == null) {
        throw _WcRouterRejection('No signer available for chain $chainId');
      }

      final signerAddress = (await signer.address).hexEip55.toLowerCase();
      final approvedAddresses =
          _approvedAddressesForChain(session, event.chainId);
      if (!approvedAddresses.contains(signerAddress)) {
        throw _WcRouterRejection(
          'Signer address $signerAddress is not approved for ${event.chainId}',
        );
      }

      final result = await _handleRequest(
        event: event,
        signer: signer,
        chainId: chainId,
        signerAddress: signerAddress,
        approvedAddresses: approvedAddresses,
      );

      return JsonRpcResponse<Object?>(
        id: event.id,
        result: result,
      );
    } on _WcRouterRejection catch (err) {
      _log('Rejecting ${event.method}: ${err.message} (code 4001)');
      return JsonRpcResponse<Object?>(
        id: event.id,
        error: const JsonRpcError(code: 4001, message: 'User rejected.'),
      );
    }
  }

  Future<String> _handleRequest({
    required SessionRequestEvent event,
    required WcSigner signer,
    required int chainId,
    required String signerAddress,
    required Set<String> approvedAddresses,
  }) async {
    switch (event.method) {
      case 'personal_sign':
        final params = _asList(event.params, method: event.method);
        if (params.length < 2) {
          throw _WcRouterRejection('personal_sign requires two parameters');
        }
        final firstAddress = _maybeAddress(params[0]);
        final secondAddress = _maybeAddress(params[1]);
        String? from;
        dynamic payload;
        if (firstAddress != null && secondAddress == null) {
          from = firstAddress;
          payload = params[1];
        } else if (secondAddress != null && firstAddress == null) {
          from = secondAddress;
          payload = params[0];
        } else if (secondAddress != null) {
          from = secondAddress;
          payload = params[0];
        } else {
          throw _WcRouterRejection('personal_sign missing address parameter');
        }
        _ensureAuthorized(from, approvedAddresses, signerAddress);
        return signer.personalSign(payload);

      case 'eth_sign':
        final params = _asList(event.params, method: event.method);
        if (params.length < 2) {
          throw _WcRouterRejection('eth_sign requires an address and payload');
        }
        final from = _requireAddress(params[0]);
        _ensureAuthorized(from, approvedAddresses, signerAddress);
        return signer.ethSign(params[1]);

      case 'eth_signTypedData':
      case 'eth_signTypedData_v4':
        final params = _asList(event.params, method: event.method);
        if (params.length < 2) {
          throw _WcRouterRejection(
            '${event.method} requires an address and typed data',
          );
        }
        final from = _requireAddress(params[0]);
        _ensureAuthorized(from, approvedAddresses, signerAddress);
        final typedData = _parseTypedData(params[1]);
        if (event.method == 'eth_signTypedData_v4') {
          return signer.signTypedDataV4Hex(typedData);
        }
        return signer.signTypedDataHex(typedData);

      case 'eth_signTransaction':
      case 'eth_sendTransaction':
        final params = _asList(event.params, method: event.method);
        if (params.isEmpty) {
          throw _WcRouterRejection(
            '${event.method} requires a transaction payload',
          );
        }
        final tx = _requireMap(params[0], context: 'transaction');
        final from = _requireAddress(tx['from']);
        _ensureAuthorized(from, approvedAddresses, signerAddress);
        final txChainId = _parseOptionalChainId(tx['chainId']);
        if (txChainId != null && txChainId != chainId) {
          throw _WcRouterRejection(
            'Transaction chainId $txChainId does not match request chain $chainId',
          );
        }
        if (event.method == 'eth_sendTransaction') {
          return signer.sendTransaction(Map<String, dynamic>.from(tx),
              chainId: chainId);
        }
        return signer.signTransaction(Map<String, dynamic>.from(tx),
            chainId: chainId);

      default:
        throw _WcRouterRejection('Unsupported method ${event.method}');
    }
  }

  int _parseChainId(String chainId) {
    final parts = chainId.split(':');
    if (parts.length != 2) {
      throw _WcRouterRejection('Invalid chain format: $chainId');
    }
    final reference = parts[1];
    final parsed = int.tryParse(reference);
    if (parsed == null) {
      throw _WcRouterRejection('Invalid chain reference: $chainId');
    }
    return parsed;
  }

  Set<String> _approvedAddressesForChain(
    SessionData session,
    String chain,
  ) {
    final parts = chain.split(':');
    if (parts.length != 2) {
      return <String>{};
    }
    final namespace = parts[0];
    final reference = parts[1];
    final namespaceData = session.namespaces[namespace];
    if (namespaceData == null) {
      return <String>{};
    }
    return namespaceData.accounts
        .map((account) => account.split(':'))
        .where((accountParts) =>
            accountParts.length == 3 && accountParts[1] == reference)
        .map((accountParts) => accountParts[2].toLowerCase())
        .toSet();
  }

  List<dynamic> _asList(
    dynamic value, {
    required String method,
  }) {
    if (value is List) {
      return value;
    }
    throw _WcRouterRejection('$method parameters must be an array');
  }

  Map<String, dynamic> _requireMap(
    dynamic value, {
    required String context,
  }) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw _WcRouterRejection('Invalid $context payload');
  }

  String? _maybeAddress(dynamic value) {
    if (value is String && value.startsWith('0x') && value.length == 42) {
      return value.toLowerCase();
    }
    return null;
  }

  String _requireAddress(dynamic value) {
    final address = _maybeAddress(value);
    if (address == null) {
      throw _WcRouterRejection('Invalid address parameter: $value');
    }
    return address;
  }

  void _ensureAuthorized(
    String? from,
    Set<String> approved,
    String signerAddress,
  ) {
    final normalized = from?.toLowerCase();
    if (normalized == null) {
      throw _WcRouterRejection('Missing from address');
    }
    if (!approved.contains(normalized)) {
      throw _WcRouterRejection('Address $normalized not approved for session');
    }
    if (normalized != signerAddress) {
      throw _WcRouterRejection(
        'Address $normalized does not match active signer $signerAddress',
      );
    }
  }

  Map<String, dynamic> _parseTypedData(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.cast<String, dynamic>();
        }
      } catch (_) {
        throw _WcRouterRejection('Unable to parse typed data payload');
      }
    }
    throw _WcRouterRejection('Invalid typed data payload');
  }

  int? _parseOptionalChainId(dynamic value) {
    if (value == null) {
      return null;
    }
    final bigInt = _parseBigInt(value);
    return bigInt?.toInt();
  }

  BigInt? _parseBigInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is BigInt) {
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
        if (trimmed.length <= 2) {
          return BigInt.zero;
        }
        return BigInt.parse(trimmed.substring(2), radix: 16);
      }
      return BigInt.parse(trimmed);
    }
    throw _WcRouterRejection('Invalid numeric value: $value');
  }

  void _log(String message) {
    debugPrint('[WalletConnect] $message');
  }
}

class _WcRouterRejection implements Exception {
  const _WcRouterRejection(this.message);

  final String message;
}
