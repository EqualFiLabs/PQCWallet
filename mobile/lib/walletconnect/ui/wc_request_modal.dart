import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:web3dart/crypto.dart' as w3;

import '../wc_signer.dart';

class WcRequestModal extends StatelessWidget {
  const WcRequestModal({
    super.key,
    required this.request,
    required this.session,
    required this.onApprove,
    required this.onReject,
    this.resolveEns,
    this.busy = false,
    this.unsupported = false,
  });

  final SessionRequestEvent request;
  final SessionData session;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final Future<String?> Function(String address)? resolveEns;
  final bool busy;
  final bool unsupported;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = session.peer.metadata;
    final chainLabel = _describeChain(request.chainId);
    final details = _parseRequest(request);
    final warningWidgets = <Widget>[];

    if (unsupported) {
      warningWidgets.add(
        _WarningBanner(
          icon: Icons.block,
          message:
              'This request cannot be handled automatically. You can still reject it to keep your wallet safe.',
          color: theme.colorScheme.error,
        ),
      );
    }
    if (request.method == 'eth_sign') {
      warningWidgets.add(
        _WarningBanner(
          icon: Icons.warning_amber,
          message:
              'eth_sign can expose your private key. Only approve if you fully trust the dApp and understand the payload.',
          color: theme.colorScheme.error,
        ),
      );
    }

    final sections = _buildSections(
      context: context,
      details: details,
    );

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RequestHeader(
                metadata: metadata,
                method: request.method,
                chainLabel: chainLabel,
                requestId: request.id,
              ),
              const SizedBox(height: 12),
              if (warningWidgets.isNotEmpty) ...[
                ...warningWidgets.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: w,
                    )),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: sections,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onReject,
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: busy || unsupported ? null : onApprove,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections({
    required BuildContext context,
    required _RequestDetails details,
  }) {
    final sections = <Widget>[];

    final accounts = _sessionAccountsForChain(
      session: session,
      chainId: request.chainId,
    );
    if (accounts.isNotEmpty) {
      sections.add(_SectionCard(
        title: 'Approved accounts',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              accounts.map((address) => _ChipLabel(text: address)).toList(),
        ),
      ));
    }

    if (details.transaction != null) {
      sections.add(
        _SectionCard(
          title: 'Transaction',
          child: _TransactionSummary(
            transaction: details.transaction!,
            resolveEns: resolveEns,
          ),
        ),
      );
    }

    if (details.message != null) {
      sections.add(
        _SectionCard(
          title: 'Message',
          child: _MessageSummary(
            preview: details.message!,
            resolveEns: resolveEns,
          ),
        ),
      );
    }

    if (details.typedData != null) {
      sections.add(
        _SectionCard(
          title: 'Typed data summary',
          child: _TypedDataSummary(details: details),
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        _SectionCard(
          title: 'Request payload',
          child: SelectableText(_prettyJson(details.params)),
        ),
      );
    } else if (details.params.isNotEmpty) {
      sections.add(
        _SectionCard(
          title: 'Raw parameters',
          child: SelectableText(_prettyJson(details.params)),
        ),
      );
    }

    if (sections.isEmpty) {
      return const <Widget>[];
    }
    final spaced = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      spaced.add(sections[i]);
      if (i != sections.length - 1) {
        spaced.add(const SizedBox(height: 12));
      }
    }
    return spaced;
  }
}

class _RequestHeader extends StatelessWidget {
  const _RequestHeader({
    required this.metadata,
    required this.method,
    required this.chainLabel,
    required this.requestId,
  });

  final PairingMetadata metadata;
  final String method;
  final String chainLabel;
  final int requestId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconUrl = metadata.icons.isNotEmpty ? metadata.icons.first : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DappIcon(url: iconUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metadata.name.isEmpty ? 'Unknown dApp' : metadata.name,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                chainLabel,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _ChipLabel(
                text: method,
                color: theme.colorScheme.secondary.withValues(alpha: 0.15),
                textColor: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 4),
              Text(
                'Request #$requestId',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TransactionSummary extends StatelessWidget {
  const _TransactionSummary({
    required this.transaction,
    this.resolveEns,
  });

  final Map<String, dynamic> transaction;
  final Future<String?> Function(String address)? resolveEns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = transaction['from']?.toString();
    final to = transaction['to']?.toString();
    final valueHex = transaction['value'];
    final gas = transaction['gas'];
    final gasPrice = transaction['gasPrice'];
    final maxFee = transaction['maxFeePerGas'];
    final maxPriority = transaction['maxPriorityFeePerGas'];
    final data = transaction['data'];

    final amount = _formatEther(valueHex);
    final gasLimit = _formatHexQuantity(gas);
    final gasPriceFormatted = _formatGwei(gasPrice);
    final maxFeeFormatted = _formatGwei(maxFee);
    final priorityFormatted = _formatGwei(maxPriority);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AddressSummary(label: 'From', address: from, resolveEns: resolveEns),
        _AddressSummary(label: 'To', address: to, resolveEns: resolveEns),
        if (amount != null) ...[
          Text('Value', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(amount, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
        ],
        if (gasLimit != null) _KeyValueRow(label: 'Gas limit', value: gasLimit),
        if (gasPriceFormatted != null)
          _KeyValueRow(label: 'Gas price', value: gasPriceFormatted),
        if (maxFeeFormatted != null)
          _KeyValueRow(label: 'Max fee per gas', value: maxFeeFormatted),
        if (priorityFormatted != null)
          _KeyValueRow(label: 'Max priority fee', value: priorityFormatted),
        if (data != null && data.toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Calldata', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(data.toString()),
        ],
      ],
    );
  }
}

class _MessageSummary extends StatelessWidget {
  const _MessageSummary({
    required this.preview,
    this.resolveEns,
  });

  final _MessagePreview preview;
  final Future<String?> Function(String address)? resolveEns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.from != null)
          _AddressSummary(
            label: 'Signer',
            address: preview.from,
            resolveEns: resolveEns,
          ),
        if (preview.display.isNotEmpty) ...[
          Text('Preview', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(preview.display),
          const SizedBox(height: 12),
        ],
        Text('Raw payload', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(preview.raw),
      ],
    );
  }
}

class _TypedDataSummary extends StatelessWidget {
  const _TypedDataSummary({required this.details});

  final _RequestDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = details.typedData;
    if (typed == null) {
      return SelectableText(_prettyJson(details.params));
    }
    final domain = typed.domain;
    final message = typed.message;
    final typedJson = details.typedDataJson ?? <String, dynamic>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValueRow(label: 'Primary type', value: typed.primaryType),
        if (domain['name'] != null)
          _KeyValueRow(label: 'Domain', value: domain['name'].toString()),
        if (domain['version'] != null)
          _KeyValueRow(label: 'Version', value: domain['version'].toString()),
        if (domain['chainId'] != null)
          _KeyValueRow(
            label: 'Domain chain',
            value: domain['chainId'].toString(),
          ),
        if (domain['verifyingContract'] != null)
          _KeyValueRow(
            label: 'Verifying contract',
            value: domain['verifyingContract'].toString(),
          ),
        const SizedBox(height: 12),
        Text('Message payload', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(_prettyJson(message)),
        const SizedBox(height: 12),
        Text('Full typed data', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(_prettyJson(typedJson)),
      ],
    );
  }
}

class _AddressSummary extends StatelessWidget {
  const _AddressSummary({
    required this.label,
    required this.address,
    this.resolveEns,
  });

  final String? label;
  final String? address;
  final Future<String?> Function(String address)? resolveEns;

  @override
  Widget build(BuildContext context) {
    if (address == null || address!.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) Text(label!, style: theme.textTheme.labelMedium),
          if (resolveEns == null)
            SelectableText(address!, style: theme.textTheme.bodyLarge)
          else
            FutureBuilder<String?>(
              future: resolveEns!(address!),
              builder: (context, snapshot) {
                final ens = snapshot.data;
                final waiting =
                    snapshot.connectionState == ConnectionState.waiting;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(address!, style: theme.textTheme.bodyLarge),
                    if (waiting)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if ((ens ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          ens!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({
    required this.text,
    this.color,
    this.textColor,
  });

  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}

class _DappIcon extends StatelessWidget {
  const _DappIcon({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: url == null
            ? Icon(Icons.extension, color: theme.colorScheme.primary)
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.extension, color: theme.colorScheme.primary),
              ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: SelectableText(value, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _RequestDetails {
  const _RequestDetails({
    required this.method,
    required this.params,
    this.transaction,
    this.message,
    this.typedData,
    this.typedDataJson,
  });

  final String method;
  final List<dynamic> params;
  final Map<String, dynamic>? transaction;
  final _MessagePreview? message;
  final WcTypedData? typedData;
  final Map<String, dynamic>? typedDataJson;
}

class _MessagePreview {
  const _MessagePreview({
    required this.raw,
    required this.display,
    this.from,
  });

  final String raw;
  final String display;
  final String? from;
}

_RequestDetails _parseRequest(SessionRequestEvent request) {
  final params = _asList(request.params);
  Map<String, dynamic>? tx;
  _MessagePreview? message;
  WcTypedData? typedData;
  Map<String, dynamic>? typedJson;

  switch (request.method) {
    case 'eth_sendTransaction':
    case 'eth_signTransaction':
      if (params.isNotEmpty) {
        final map = _asMap(params.first);
        if (map != null) {
          tx = map;
        }
      }
      break;
    case 'personal_sign':
      message = _parsePersonalSign(params);
      break;
    case 'eth_sign':
      message = _parseEthSign(params);
      break;
    case 'eth_signTypedData':
    case 'eth_signTypedData_v4':
      if (params.length >= 2) {
        final typed = _asMap(params[1]);
        if (typed != null) {
          typedJson = typed;
          try {
            typedData = WcTypedData.fromJson(Map<String, dynamic>.from(typed));
          } catch (_) {
            typedData = null;
          }
        }
      }
      break;
  }

  return _RequestDetails(
    method: request.method,
    params: params,
    transaction: tx,
    message: message,
    typedData: typedData,
    typedDataJson: typedJson,
  );
}

_MessagePreview? _parsePersonalSign(List<dynamic> params) {
  if (params.length < 2) {
    return null;
  }
  final firstAddress = _maybeAddress(params[0]);
  final secondAddress = _maybeAddress(params[1]);
  dynamic payload;
  String? from;
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
    payload = params[0];
  }
  return _messageFromPayload(payload, from: from);
}

_MessagePreview? _parseEthSign(List<dynamic> params) {
  if (params.length < 2) {
    return null;
  }
  final from = _maybeAddress(params[0]);
  final payload = params[1];
  return _messageFromPayload(payload, from: from);
}

_MessagePreview _messageFromPayload(dynamic payload, {String? from}) {
  if (payload == null) {
    return _MessagePreview(raw: '', display: '', from: from);
  }
  if (payload is String) {
    final trimmed = payload.trim();
    if (_looksLikeHex(trimmed)) {
      final ascii = _tryDecodeHex(trimmed);
      if (ascii.trim().isNotEmpty) {
        return _MessagePreview(raw: trimmed, display: ascii, from: from);
      }
      return _MessagePreview(raw: trimmed, display: trimmed, from: from);
    }
    return _MessagePreview(raw: trimmed, display: trimmed, from: from);
  }
  if (payload is List) {
    final bytes = Uint8List.fromList(payload.cast<int>());
    final ascii = utf8.decode(bytes, allowMalformed: true);
    final raw = '0x${w3.bytesToHex(bytes, include0x: false)}';
    return _MessagePreview(raw: raw, display: ascii, from: from);
  }
  return _MessagePreview(
      raw: payload.toString(), display: payload.toString(), from: from);
}

List<dynamic> _asList(dynamic value) {
  if (value is List) {
    return value;
  }
  if (value == null) {
    return const <dynamic>[];
  }
  return <dynamic>[value];
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

String? _maybeAddress(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('0x') && trimmed.length == 42) {
      return trimmed;
    }
  }
  return null;
}

String _prettyJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}

String? _formatEther(dynamic value) {
  final big = _parseHexQuantity(value);
  if (big == null) {
    return null;
  }
  final amount = EtherAmount.fromBigInt(EtherUnit.wei, big);
  final inEther = amount.getValueInUnit(EtherUnit.ether);
  final formatted =
      inEther >= 1 ? inEther.toStringAsFixed(4) : inEther.toStringAsFixed(8);
  return '$formatted ETH';
}

String? _formatGwei(dynamic value) {
  final big = _parseHexQuantity(value);
  if (big == null) {
    return null;
  }
  final amount = EtherAmount.fromBigInt(EtherUnit.wei, big);
  final inGwei = amount.getValueInUnit(EtherUnit.gwei);
  return '${inGwei.toStringAsFixed(2)} gwei';
}

String? _formatHexQuantity(dynamic value) {
  final big = _parseHexQuantity(value);
  return big?.toString();
}

BigInt? _parseHexQuantity(dynamic value) {
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
      final normalized = trimmed.substring(2);
      if (normalized.isEmpty) {
        return BigInt.zero;
      }
      return BigInt.parse(normalized, radix: 16);
    }
    return BigInt.tryParse(trimmed);
  }
  return null;
}

bool _looksLikeHex(String value) {
  final trimmed = value.trim();
  final normalized = trimmed.startsWith('0x') || trimmed.startsWith('0X')
      ? trimmed.substring(2)
      : trimmed;
  if (normalized.isEmpty) {
    return false;
  }
  final hex = RegExp(r'^[0-9a-fA-F]+$');
  return hex.hasMatch(normalized);
}

String _tryDecodeHex(String hex) {
  final normalized =
      hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;
  if (normalized.isEmpty) {
    return '';
  }
  final even = normalized.length.isEven ? normalized : '0$normalized';
  try {
    final bytes = w3.hexToBytes(even);
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return '';
  }
}

List<String> _sessionAccountsForChain({
  required SessionData session,
  required String chainId,
}) {
  final accounts = <String>{};
  session.namespaces.forEach((_, namespace) {
    for (final account in namespace.accounts) {
      if (NamespaceUtils.getChainFromAccount(account) == chainId) {
        accounts.add(account.split(':').last);
      }
    }
  });
  final sorted = accounts.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return sorted;
}

String _describeChain(String chainId) {
  switch (chainId) {
    case 'eip155:8453':
      return 'Base Mainnet (eip155:8453)';
    case 'eip155:84532':
      return 'Base Sepolia (eip155:84532)';
    default:
      return chainId;
  }
}
