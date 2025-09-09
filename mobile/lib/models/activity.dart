import 'dart:convert';

enum ActivityStatus { pending, sent, confirmed, failed, dropped }

class ActivityItem {
  final String userOpHash;
  final String to;
  final String display;
  final int ts;
  final ActivityStatus status;
  final String? txHash;
  final int chainId;
  final String opKind;
  final String? tokenSymbol;
  final String? tokenAddress;

  const ActivityItem({
    required this.userOpHash,
    required this.to,
    required this.display,
    required this.ts,
    required this.status,
    required this.chainId,
    required this.opKind,
    this.txHash,
    this.tokenSymbol,
    this.tokenAddress,
  });

  ActivityItem copyWith({ActivityStatus? status, String? txHash}) => ActivityItem(
        userOpHash: userOpHash,
        to: to,
        display: display,
        ts: ts,
        status: status ?? this.status,
        chainId: chainId,
        opKind: opKind,
        txHash: txHash ?? this.txHash,
        tokenSymbol: tokenSymbol,
        tokenAddress: tokenAddress,
      );

  Map<String, dynamic> toJson() => {
        'userOpHash': userOpHash,
        'to': to,
        'display': display,
        'ts': ts,
        'status': status.name,
        'txHash': txHash,
        'chainId': chainId,
        'opKind': opKind,
        'tokenSymbol': tokenSymbol,
        'tokenAddress': tokenAddress,
      };

  static ActivityItem fromJson(Map<String, dynamic> j) => ActivityItem(
        userOpHash: j['userOpHash'],
        to: j['to'],
        display: j['display'],
        ts: (j['ts'] as num).toInt(),
        status: ActivityStatus.values.firstWhere(
            (e) => e.name == j['status'],
            orElse: () => ActivityStatus.sent),
        txHash: j['txHash'],
        chainId: (j['chainId'] as num).toInt(),
        opKind: j['opKind'] ?? 'eth',
        tokenSymbol: j['tokenSymbol'],
        tokenAddress: j['tokenAddress'],
      );

  static String encodeList(List<ActivityItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<ActivityItem> decodeList(String s) =>
      (jsonDecode(s) as List)
          .cast<Map<String, dynamic>>()
          .map(fromJson)
          .toList();
}
