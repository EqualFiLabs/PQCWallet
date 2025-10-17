import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart' as w3;
import 'package:web3dart/web3dart.dart';

class WcSigner {
  const WcSigner({
    required Credentials credentials,
  }) : _credentials = credentials;

  final Credentials _credentials;

  Credentials get credentials => _credentials;

  Future<Uint8List> sign(Uint8List payload) async {
    final signature = await _credentials.signToEcSignature(payload);
    return _signatureToBytes(signature);
  }

  Future<Uint8List> signTypedData(Map<String, dynamic> payload) async {
    final typedData = parseTypedDataPayload(payload);
    final signable = typedDataMessage(typedData);
    final signature = await _credentials.signToEcSignature(signable);
    return _signatureToBytes(signature);
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
}

Uint8List _signatureToBytes(w3.MsgSignature signature) {
  final r = _padLeft(w3.intToBytes(signature.r));
  final s = _padLeft(w3.intToBytes(signature.s));
  final out = Uint8List(65);
  out.setRange(0, 32, r);
  out.setRange(32, 64, s);
  out[64] = signature.v;
  return out;
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
