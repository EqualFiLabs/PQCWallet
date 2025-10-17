import 'dart:convert';
import 'dart:typed_data';

import 'package:pqc_wallet/services/rpc.dart';
import 'package:web3dart/crypto.dart' as w3;
import 'package:web3dart/web3dart.dart';

class WcSigner {
  WcSigner({
    required Credentials credentials,
    required RpcClient rpcClient,
    int? defaultChainId,
  })  : _credentials = credentials,
        _rpcClient = rpcClient,
        _defaultChainId = defaultChainId;

  final Credentials _credentials;
  final RpcClient _rpcClient;
  final int? _defaultChainId;

  EthereumAddress? _cachedAddress;
  bool? _supportsEip1559Cache;

  Credentials get credentials => _credentials;

  RpcClient get rpcClient => _rpcClient;

  int? get defaultChainId => _defaultChainId;

  Future<EthereumAddress> get address async {
    final cached = _cachedAddress;
    if (cached != null) {
      return cached;
    }
    final resolved = _credentials.address;
    _cachedAddress = resolved;
    return resolved;
  }

  Future<String> personalSign(dynamic message) async {
    final messageBytes = _coerceMessageBytes(message);
    final signature = _credentials.signPersonalMessageToUint8List(messageBytes);
    return w3.bytesToHex(signature, include0x: true);
  }

  Future<String> ethSign(dynamic message) async {
    final messageBytes = _coerceMessageBytes(message);
    final signature = _credentials.signToUint8List(messageBytes);
    return w3.bytesToHex(signature, include0x: true);
  }

  Future<String> signTypedDataHex(Map<String, dynamic> payload) async {
    final signature = await signTypedData(payload);
    return w3.bytesToHex(signature, include0x: true);
  }

  Future<String> signTypedDataV4Hex(Map<String, dynamic> payload) {
    return signTypedDataHex(payload);
  }

  Future<String> sendTransaction(
    Map<String, dynamic> payload, {
    int? chainId,
  }) async {
    final raw = await _signTransactionPayload(
      payload,
      chainId: chainId ?? _defaultChainId,
    );
    final rawHex = w3.bytesToHex(raw, include0x: true);
    final result = await _rpcClient.call('eth_sendRawTransaction', [rawHex]);
    return _normalizeHex(result.toString());
  }

  Future<String> signTransaction(
    Map<String, dynamic> payload, {
    int? chainId,
  }) async {
    final raw = await _signTransactionPayload(
      payload,
      chainId: chainId ?? _defaultChainId,
    );
    return w3.bytesToHex(raw, include0x: true);
  }

  Future<Uint8List> sign(Uint8List payload) async {
    final signature = _credentials.signToUint8List(payload);
    return Uint8List.fromList(signature);
  }

  Future<Uint8List> signTypedData(Map<String, dynamic> payload) async {
    final typedData = parseTypedDataPayload(payload);
    final signable = typedDataMessage(typedData);
    final signature = _credentials.signToUint8List(signable);
    return Uint8List.fromList(signature);
  }

  WcTypedData parseTypedDataPayload(Map<String, dynamic> payload) {
    return WcTypedData.fromJson(payload);
  }

  Uint8List hashDomain(WcTypedData typedData) {
    return hashStruct(typedData, typedData.domain, typeName: 'EIP712Domain');
  }

  Uint8List hashStruct(
    WcTypedData typedData,
    Map<String, dynamic> data, {
    String? typeName,
  }) {
    final typeToHash = typeName ?? typedData.primaryType;
    return typedData.hashStruct(typeToHash, data);
  }

  Uint8List typedDataDigest(WcTypedData typedData) {
    return typedData.digest();
  }

  Uint8List typedDataMessage(WcTypedData typedData) {
    return typedData.signableMessage();
  }

  Uint8List _coerceMessageBytes(dynamic message) {
    if (message is Uint8List) {
      return message;
    }
    if (message is List<int>) {
      return Uint8List.fromList(message);
    }
    if (message is String) {
      final trimmed = message.trim();
      if (trimmed.isEmpty) {
        return Uint8List(0);
      }
      if (_looksLikeHex(trimmed)) {
        return Uint8List.fromList(
          w3.hexToBytes(_ensureHexPrefix(trimmed)),
        );
      }
      return Uint8List.fromList(utf8.encode(trimmed));
    }
    throw ArgumentError('Unsupported message payload: $message');
  }

  bool _looksLikeHex(String value) {
    final normalized = (value.startsWith('0x') || value.startsWith('0X'))
        ? value.substring(2)
        : value;
    if (normalized.isEmpty) {
      return false;
    }
    final hex = RegExp(r'^[0-9a-fA-F]+$');
    return hex.hasMatch(normalized);
  }

  String _ensureHexPrefix(String value) {
    final normalized = (value.startsWith('0x') || value.startsWith('0X'))
        ? value.substring(2)
        : value;
    final even = normalized.length.isEven ? normalized : '0$normalized';
    return '0x${even.toLowerCase()}';
  }

  Future<Uint8List> _signTransactionPayload(
    Map<String, dynamic> payload, {
    int? chainId,
  }) async {
    final resolvedChainId = chainId;
    if (resolvedChainId == null) {
      throw ArgumentError('chainId must be provided for transaction signing');
    }

    final prepared = await _prepareTransaction(
      Map<String, dynamic>.from(payload),
    );

    final signed = signTransactionRaw(
      prepared.transaction,
      _credentials,
      chainId: resolvedChainId,
    );

    if (prepared.transaction.isEIP1559) {
      return prependTransactionType(0x02, signed);
    }
    return signed;
  }

  Future<_PreparedTransaction> _prepareTransaction(
    Map<String, dynamic> payload,
  ) async {
    final fromHex = _normalizeHexAddress(payload['from']);
    if (fromHex == null) {
      throw ArgumentError('Transaction is missing a valid "from" address');
    }
    final from = EthereumAddress.fromHex(fromHex);

    final toHex = _normalizeHexAddress(payload['to']);
    final to = toHex != null ? EthereumAddress.fromHex(toHex) : null;

    final data = _transactionDataBytes(payload['data']);
    final value = _bigIntFrom(payload['value']);
    final nonce = _bigIntFrom(payload['nonce']);
    final gasLimitInput = _bigIntFrom(payload['gas'] ?? payload['gasLimit']);
    final gasPriceInput = _bigIntFrom(payload['gasPrice']);
    final maxFeeInput = _bigIntFrom(payload['maxFeePerGas']);
    final maxPriorityInput = _bigIntFrom(payload['maxPriorityFeePerGas']);
    final explicitType = (payload['type'] as String?)?.toLowerCase();

    final supports1559 = await _supportsEip1559();
    final fees = await _resolveFees(
      supportsEip1559: supports1559,
      explicitType: explicitType,
      gasPrice: gasPriceInput,
      maxFeePerGas: maxFeeInput,
      maxPriorityFeePerGas: maxPriorityInput,
    );

    var gasLimit = gasLimitInput;
    if (gasLimit == null ||
        gasLimit <= BigInt.zero ||
        gasLimit > _maxReasonableGasLimit) {
      gasLimit = await _estimateGas(
        from: fromHex,
        to: toHex,
        data: data,
        value: value,
        fees: fees,
      );
    }

    final resolvedNonce = await _resolveNonce(fromHex, nonce);

    final transaction = Transaction(
      from: from,
      to: to,
      data: data,
      value: value != null ? EtherAmount.inWei(value) : null,
      nonce: resolvedNonce,
      gasPrice: fees.legacyGasPrice != null
          ? EtherAmount.inWei(fees.legacyGasPrice!)
          : null,
      maxFeePerGas: fees.maxFeePerGas != null
          ? EtherAmount.inWei(fees.maxFeePerGas!)
          : null,
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas != null
          ? EtherAmount.inWei(fees.maxPriorityFeePerGas!)
          : null,
      maxGas: gasLimit.toInt(),
    );

    return _PreparedTransaction(transaction: transaction, gasLimit: gasLimit);
  }

  Uint8List? _transactionDataBytes(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final prefixed = _ensureHexPrefix(trimmed);
      return Uint8List.fromList(w3.hexToBytes(prefixed));
    }
    throw ArgumentError('Unsupported transaction data: $value');
  }

  Future<int> _resolveNonce(String from, BigInt? provided) async {
    if (provided != null) {
      return provided.toInt();
    }
    final response = await _rpcClient.call(
      'eth_getTransactionCount',
      [from, 'pending'],
    );
    final parsed = _bigIntFrom(response);
    if (parsed == null) {
      throw StateError('Unable to determine nonce for $from');
    }
    return parsed.toInt();
  }

  Future<_FeeConfiguration> _resolveFees({
    required bool supportsEip1559,
    String? explicitType,
    BigInt? gasPrice,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
  }) async {
    final typeHint = explicitType?.toLowerCase();
    final forceLegacy = typeHint == '0x0' || typeHint == '0x1';
    final force1559 = typeHint == '0x2';

    if (!supportsEip1559 || forceLegacy) {
      final resolvedGasPrice = await _resolveLegacyGasPrice(gasPrice);
      return _FeeConfiguration.legacy(resolvedGasPrice);
    }

    if (!force1559 && gasPrice != null && maxFeePerGas == null) {
      maxFeePerGas = gasPrice;
    }
    if (!force1559 && gasPrice != null && maxPriorityFeePerGas == null) {
      maxPriorityFeePerGas = gasPrice;
    }

    final resolvedPriority = await _resolvePriorityFee(maxPriorityFeePerGas);
    final baseFee = await _latestBaseFeePerGas();
    final minimumMaxFee = baseFee * BigInt.two + resolvedPriority;

    var resolvedMaxFee = maxFeePerGas;
    if (resolvedMaxFee == null ||
        resolvedMaxFee < resolvedPriority ||
        resolvedMaxFee < minimumMaxFee ||
        _isExtremeFee(resolvedMaxFee)) {
      resolvedMaxFee =
          minimumMaxFee > resolvedPriority ? minimumMaxFee : resolvedPriority;
    }

    if (resolvedMaxFee < resolvedPriority) {
      resolvedMaxFee = resolvedPriority;
    }

    return _FeeConfiguration.eip1559(
      maxFeePerGas: resolvedMaxFee,
      maxPriorityFeePerGas: resolvedPriority,
    );
  }

  Future<BigInt> _resolveLegacyGasPrice(BigInt? provided) async {
    if (provided != null &&
        provided > BigInt.zero &&
        !_isExtremeFee(provided)) {
      return provided;
    }
    try {
      final response = await _rpcClient.call('eth_gasPrice', []);
      final parsed = _bigIntFrom(response);
      if (parsed != null && parsed > BigInt.zero) {
        return parsed;
      }
    } catch (_) {
      // Ignore and fall back to default value.
    }
    return BigInt.from(2) * _gwei;
  }

  Future<BigInt> _resolvePriorityFee(BigInt? provided) async {
    if (provided != null &&
        provided > BigInt.zero &&
        !_isExtremeFee(provided)) {
      return provided;
    }
    try {
      final suggested = await _rpcClient.maxPriorityFeePerGas();
      if (suggested > BigInt.zero) {
        return suggested;
      }
    } catch (_) {
      // Ignore and fall back to default value.
    }
    return BigInt.from(2) * _gwei;
  }

  Future<BigInt> _latestBaseFeePerGas() async {
    try {
      final block = await _rpcClient.call(
        'eth_getBlockByNumber',
        ['latest', false],
      );
      if (block is Map && block['baseFeePerGas'] != null) {
        final parsed = _bigIntFrom(block['baseFeePerGas']);
        if (parsed != null) {
          return parsed;
        }
      }
    } catch (_) {
      // Ignore and fall through to zero.
    }
    return BigInt.zero;
  }

  Future<bool> _supportsEip1559() async {
    final cached = _supportsEip1559Cache;
    if (cached != null) {
      return cached;
    }
    final latestBase = await _latestBaseFeePerGas();
    final supported = latestBase > BigInt.zero;
    _supportsEip1559Cache = supported;
    return supported;
  }

  Future<BigInt> _estimateGas({
    required String from,
    String? to,
    Uint8List? data,
    BigInt? value,
    required _FeeConfiguration fees,
  }) async {
    final payload = <String, dynamic>{
      'from': from,
    };
    if (to != null) {
      payload['to'] = to;
    }
    if (data != null && data.isNotEmpty) {
      payload['data'] = '0x${w3.bytesToHex(data, include0x: false)}';
    }
    if (value != null && value > BigInt.zero) {
      payload['value'] = _encodeQuantity(value);
    }

    if (fees.is1559) {
      payload['type'] = '0x2';
      payload['maxFeePerGas'] = _encodeQuantity(fees.maxFeePerGas!);
      payload['maxPriorityFeePerGas'] =
          _encodeQuantity(fees.maxPriorityFeePerGas!);
    } else {
      payload['gasPrice'] = _encodeQuantity(fees.legacyGasPrice!);
    }

    final response = await _rpcClient.call('eth_estimateGas', [payload]);
    final parsed = _bigIntFrom(response);
    if (parsed == null || parsed <= BigInt.zero) {
      throw StateError('Failed to estimate gas');
    }
    return parsed;
  }

  String? _normalizeHexAddress(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
        if (trimmed.length == 42) {
          return '0x${trimmed.substring(2).toLowerCase()}';
        }
      }
    }
    return null;
  }

  BigInt? _bigIntFrom(dynamic value) {
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
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return null;
      }
      if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
        if (normalized.length <= 2) {
          return BigInt.zero;
        }
        return BigInt.parse(normalized.substring(2), radix: 16);
      }
      return BigInt.parse(normalized);
    }
    throw ArgumentError('Unsupported numeric value: $value');
  }

  bool _isExtremeFee(BigInt value) {
    return value <= BigInt.zero || value > _maxReasonableGasPrice;
  }

  String _encodeQuantity(BigInt value) {
    if (value <= BigInt.zero) {
      return '0x0';
    }
    return '0x${value.toRadixString(16)}';
  }

  String _normalizeHex(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '0x0';
    }
    return trimmed.startsWith('0x') || trimmed.startsWith('0X')
        ? '0x${trimmed.substring(2).toLowerCase()}'
        : '0x${trimmed.toLowerCase()}';
  }

  static final BigInt _gwei = BigInt.from(1000000000);
  static final BigInt _maxReasonableGasLimit = BigInt.from(30000000);
  static final BigInt _maxReasonableGasPrice = BigInt.from(1000) * _gwei;
}

class _PreparedTransaction {
  const _PreparedTransaction({
    required this.transaction,
    required this.gasLimit,
  });

  final Transaction transaction;
  final BigInt gasLimit;
}

class _FeeConfiguration {
  const _FeeConfiguration._({
    required this.is1559,
    this.legacyGasPrice,
    this.maxFeePerGas,
    this.maxPriorityFeePerGas,
  });

  final bool is1559;
  final BigInt? legacyGasPrice;
  final BigInt? maxFeePerGas;
  final BigInt? maxPriorityFeePerGas;

  static _FeeConfiguration legacy(BigInt gasPrice) {
    return _FeeConfiguration._(
      is1559: false,
      legacyGasPrice: gasPrice,
    );
  }

  static _FeeConfiguration eip1559({
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
  }) {
    return _FeeConfiguration._(
      is1559: true,
      maxFeePerGas: maxFeePerGas,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
    );
  }
}

Uint8List _padLeft(Uint8List bytes) {
  var trimmed = bytes;
  while (trimmed.length > 32 && trimmed.first == 0) {
    trimmed = trimmed.sublist(1);
  }
  if (trimmed.length > 32) {
    throw ArgumentError('Value exceeds 32 bytes');
  }
  final result = Uint8List(32);
  result.setRange(32 - trimmed.length, 32, trimmed);
  return result;
}

class WcTypedDataField {
  const WcTypedDataField({
    required this.name,
    required this.type,
  });

  final String name;
  final String type;
}

class WcTypedData {
  WcTypedData._({
    required Map<String, List<WcTypedDataField>> types,
    required this.primaryType,
    required Map<String, dynamic> domain,
    required Map<String, dynamic> message,
  })  : types = Map.unmodifiable({
          for (final entry in types.entries)
            entry.key: List<WcTypedDataField>.unmodifiable(entry.value),
        }),
        domain = Map.unmodifiable(domain),
        message = Map.unmodifiable(message);

  factory WcTypedData.fromJson(Map<String, dynamic> payload) {
    final typesValue = payload['types'];
    if (typesValue is! Map<String, dynamic>) {
      throw ArgumentError('types must be a map');
    }

    final parsedTypes = <String, List<WcTypedDataField>>{};
    for (final entry in typesValue.entries) {
      final typeName = entry.key;
      final fieldsValue = entry.value;
      if (fieldsValue is! List) {
        throw ArgumentError('Type $typeName must be a list of fields');
      }
      final fields = <WcTypedDataField>[];
      for (final field in fieldsValue) {
        if (field is! Map<String, dynamic>) {
          throw ArgumentError('Invalid field definition for $typeName');
        }
        final name = field['name'];
        final type = field['type'];
        if (name is! String || type is! String) {
          throw ArgumentError('Invalid field entry for $typeName');
        }
        fields.add(WcTypedDataField(name: name, type: type));
      }
      parsedTypes[typeName] = fields;
    }

    parsedTypes.putIfAbsent('EIP712Domain', () => const <WcTypedDataField>[]);

    final primaryType = payload['primaryType'];
    if (primaryType is! String) {
      throw ArgumentError('primaryType must be provided');
    }

    final domainValue = payload['domain'];
    if (domainValue is! Map<String, dynamic>) {
      throw ArgumentError('domain must be provided');
    }
    final messageValue = payload['message'];
    if (messageValue is! Map<String, dynamic>) {
      throw ArgumentError('message must be provided');
    }

    return WcTypedData._(
      types: parsedTypes,
      primaryType: primaryType,
      domain: Map<String, dynamic>.from(domainValue),
      message: Map<String, dynamic>.from(messageValue),
    );
  }

  final Map<String, List<WcTypedDataField>> types;
  final String primaryType;
  final Map<String, dynamic> domain;
  final Map<String, dynamic> message;

  late final _Eip712Encoder _encoder = _Eip712Encoder(types);

  Uint8List encodeData(String typeName, Map<String, dynamic> value) {
    return _encoder.encodeData(typeName, value);
  }

  Uint8List hashStruct(String typeName, Map<String, dynamic> value) {
    return _encoder.hashStruct(typeName, value);
  }

  Uint8List domainSeparator() => hashStruct('EIP712Domain', domain);

  Uint8List structHash() => hashStruct(primaryType, message);

  Uint8List signableMessage() {
    final ds = domainSeparator();
    final sh = structHash();
    final out = Uint8List(2 + ds.length + sh.length);
    out.setRange(0, 2, const [0x19, 0x01]);
    out.setRange(2, 2 + ds.length, ds);
    out.setRange(2 + ds.length, out.length, sh);
    return out;
  }

  Uint8List digest() => w3.keccak256(signableMessage());
}

class _Eip712Encoder {
  _Eip712Encoder(this._types);

  final Map<String, List<WcTypedDataField>> _types;

  static final RegExp _arrayType = RegExp(r'^(.*)\[(\d*)\]$');

  Uint8List hashStruct(String primaryType, Map<String, dynamic> data) {
    final encoded = encodeData(primaryType, data);
    return w3.keccak256(encoded);
  }

  Uint8List encodeData(String primaryType, Map<String, dynamic> data) {
    final fields = _types[primaryType];
    if (fields == null) {
      throw ArgumentError('Unknown type $primaryType');
    }
    final builder = BytesBuilder();
    builder.add(typeHash(primaryType));
    for (final field in fields) {
      final value = data[field.name];
      builder.add(_encodeValue(field.type, value));
    }
    return builder.toBytes();
  }

  Uint8List typeHash(String primaryType) {
    return w3.keccakUtf8(_encodeType(primaryType));
  }

  String _encodeType(String primaryType) {
    final deps = _findDependencies(primaryType)..remove(primaryType);
    final order = <String>[primaryType, ...deps.toList()..sort()];
    final buffer = StringBuffer();
    for (final typeName in order) {
      final fields = _types[typeName];
      if (fields == null) {
        throw ArgumentError('Type $typeName not defined');
      }
      buffer
        ..write(typeName)
        ..write('(')
        ..write(fields.map((f) => '${f.type} ${f.name}').join(','))
        ..write(')');
    }
    return buffer.toString();
  }

  Set<String> _findDependencies(String primaryType, [Set<String>? deps]) {
    final dependencies = deps ?? <String>{};
    final fields = _types[primaryType];
    if (fields == null) {
      return dependencies;
    }
    for (final field in fields) {
      final baseType = _baseType(field.type);
      if (!_types.containsKey(baseType)) {
        continue;
      }
      if (dependencies.add(baseType)) {
        _findDependencies(baseType, dependencies);
      }
    }
    return dependencies;
  }

  String _baseType(String type) {
    final match = _arrayType.firstMatch(type);
    if (match != null) {
      return match.group(1)!;
    }
    return type;
  }

  Uint8List _encodeValue(String type, dynamic value) {
    if (value == null) {
      return Uint8List(32);
    }
    final arrayMatch = _arrayType.firstMatch(type);
    if (arrayMatch != null) {
      return _encodeArray(arrayMatch, value);
    }
    if (_types.containsKey(type)) {
      final mapValue = _asMap(value);
      return w3.keccak256(encodeData(type, mapValue));
    }
    switch (type) {
      case 'string':
        return w3.keccak256(utf8.encode(value as String));
      case 'bytes':
        return w3.keccak256(_asBytes(value));
      case 'bool':
        final boolValue = value is bool
            ? value
            : (value is String
                ? value.toLowerCase() == 'true'
                : value == 1 || value == '1');
        return _encodeUnsigned(BigInt.from(boolValue ? 1 : 0), 256);
      case 'address':
        return _padLeft(_addressBytes(value));
    }
    if (type.startsWith('bytes')) {
      final size = int.tryParse(type.substring(5));
      if (size == null || size < 1 || size > 32) {
        throw ArgumentError('Invalid bytes<N> size for $type');
      }
      final bytes = _asBytes(value);
      if (bytes.length != size) {
        throw ArgumentError('Expected $size bytes for $type');
      }
      return _padRight(bytes);
    }
    if (type.startsWith('uint')) {
      final bits = _parseBitSize(type, 256);
      return _encodeUnsigned(_asBigInt(value), bits);
    }
    if (type.startsWith('int')) {
      final bits = _parseBitSize(type, 256);
      return _encodeSigned(_asBigInt(value), bits);
    }
    throw ArgumentError('Unsupported type $type');
  }

  Uint8List _encodeArray(RegExpMatch match, dynamic value) {
    if (value == null) {
      return Uint8List(32);
    }
    if (value is! List) {
      throw ArgumentError('Expected list for array type ${match.group(0)}');
    }
    final baseType = match.group(1)!;
    final fixedLength = match.group(2);
    if (fixedLength != null && fixedLength.isNotEmpty) {
      final expected = int.parse(fixedLength);
      if (value.length != expected) {
        throw ArgumentError(
          'Expected array of length $expected for type ${match.group(0)}',
        );
      }
    }
    final builder = BytesBuilder();
    for (final element in value) {
      builder.add(_encodeValue(baseType, element));
    }
    return w3.keccak256(builder.toBytes());
  }

  Uint8List _encodeUnsigned(BigInt value, int bits) {
    if (value.isNegative) {
      throw ArgumentError('Unsigned value cannot be negative');
    }
    final maxValue = BigInt.one << bits;
    if (value >= maxValue) {
      throw ArgumentError('Value exceeds uint$bits range');
    }
    return _padLeft(w3.intToBytes(value));
  }

  Uint8List _encodeSigned(BigInt value, int bits) {
    final limit = BigInt.one << (bits - 1);
    if (value < -limit || value >= limit) {
      throw ArgumentError('Value exceeds int$bits range');
    }
    final encoded = value.isNegative
        ? (BigInt.one << bits) + value
        : value.toUnsigned(bits);
    return _padLeft(w3.intToBytes(encoded));
  }

  int _parseBitSize(String type, int defaultValue) {
    final suffix = type.replaceFirst(RegExp(r'^(u?int)'), '');
    if (suffix.isEmpty) {
      return defaultValue;
    }
    final size = int.tryParse(suffix);
    if (size == null || size <= 0 || size > 256 || size % 8 != 0) {
      throw ArgumentError('Invalid numeric type $type');
    }
    return size;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw ArgumentError('Expected map value for struct');
  }

  Uint8List _asBytes(dynamic value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    if (value is String) {
      final normalized = value.startsWith('0x') ? value : '0x$value';
      return Uint8List.fromList(w3.hexToBytes(normalized));
    }
    throw ArgumentError('Invalid bytes value');
  }

  BigInt _asBigInt(dynamic value) {
    if (value is BigInt) {
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is String) {
      final normalized = value.trim();
      if (normalized.startsWith('0x') || normalized.startsWith('0X')) {
        return BigInt.parse(normalized.substring(2), radix: 16);
      }
      return BigInt.parse(normalized);
    }
    throw ArgumentError('Invalid numeric value');
  }

  Uint8List _padRight(Uint8List bytes) {
    if (bytes.length > 32) {
      throw ArgumentError('Bytes value exceeds 32 bytes');
    }
    final result = Uint8List(32);
    result.setRange(0, bytes.length, bytes);
    return result;
  }

  Uint8List _addressBytes(dynamic value) {
    if (value is EthereumAddress) {
      return value.addressBytes;
    }
    if (value is Uint8List) {
      if (value.length != 20) {
        throw ArgumentError('Address must be 20 bytes');
      }
      return value;
    }
    if (value is List<int>) {
      final bytes = Uint8List.fromList(value);
      if (bytes.length != 20) {
        throw ArgumentError('Address must be 20 bytes');
      }
      return bytes;
    }
    if (value is String) {
      final normalized = value.startsWith('0x') ? value : '0x$value';
      final bytes = Uint8List.fromList(w3.hexToBytes(normalized));
      if (bytes.length != 20) {
        throw ArgumentError('Address must be 20 bytes');
      }
      return bytes;
    }
    throw ArgumentError('Invalid address value');
  }
}
