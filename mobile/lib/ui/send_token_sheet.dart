import 'package:flutter/material.dart';
import '../models/token.dart';
import '../userop/userop_flow.dart';
import '../crypto/mnemonic.dart';
import '../state/settings.dart';
import '../models/activity.dart';
import '../services/activity_store.dart';
import '../services/eoa_transactions.dart';

class SendTokenSheet extends StatefulWidget {
  final Map<String, dynamic> cfg;
  final UserOpFlow flow;
  final KeyMaterial keys;
  final AppSettings settings;
  final ActivityStore store;
  final EOATransactions eoa;
  final Future<bool> Function(String reason) authenticate;
  const SendTokenSheet({
    super.key,
    required this.cfg,
    required this.flow,
    required this.keys,
    required this.settings,
    required this.store,
    required this.eoa,
    required this.authenticate,
  });

  @override
  State<SendTokenSheet> createState() => _SendTokenSheetState();
}

class _SendTokenSheetState extends State<SendTokenSheet> {
  ChainTokens? registry;
  String selected = 'USDC';
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final spenderCtrl = TextEditingController();
  final approveAmtCtrl = TextEditingController();
  bool usePermit = false;
  bool usePermit2 = false;
  bool useEoa = false;
  bool sending = false;
  bool approving = false;

  @override
  void initState() {
    super.initState();
    ChainTokens.load().then((r) => setState(() => registry = r));
  }

  @override
  void dispose() {
    toCtrl.dispose();
    amtCtrl.dispose();
    spenderCtrl.dispose();
    approveAmtCtrl.dispose();
    super.dispose();
  }

  BigInt _pow10(int d) => BigInt.from(10).pow(d);

  BigInt _parseAmount(String v, int decimals) {
    final parts = v.split('.');
    final whole = parts[0].isEmpty ? BigInt.zero : BigInt.parse(parts[0]);
    var frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > decimals) {
      frac = frac.substring(0, decimals);
    }
    final fracVal =
        frac.isEmpty ? BigInt.zero : BigInt.parse(frac.padRight(decimals, '0'));
    return whole * _pow10(decimals) + fracVal;
  }

  Future<void> _send() async {
    if (registry == null) return;
    final token = selected;
    final tokenInfo = registry!.token(token)!;
    final decimals = (tokenInfo['decimals'] as num).toInt();
    final amtStr = amtCtrl.text.trim();
    final amount = _parseAmount(amtStr, decimals);
    final to = toCtrl.text.trim();
    final chainId = widget.cfg['chainId'] as int;
    final tokenAddr = registry!.tokenAddress(token, chainId)!;
    if (to.isEmpty) {
      debugPrint('send error: missing recipient');
      return;
    }
    setState(() => sending = true);
    try {
      if (useEoa) {
        final txHash = await widget.eoa.sendTokenTransfer(
          keys: widget.keys,
          chainId: chainId,
          tokenAddress: tokenAddr,
          to: to,
          amount: amount,
        );
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await widget.store.upsertByUserOpHash(txHash, (existing) =>
            existing?.copyWith(status: ActivityStatus.pending, txHash: txHash) ??
            ActivityItem(
              userOpHash: txHash,
              to: to,
              display: '$amtStr $token',
              ts: ts,
              status: ActivityStatus.pending,
              chainId: chainId,
              opKind: 'erc20',
              tokenSymbol: token,
              tokenAddress: tokenAddr,
              txHash: txHash,
            ));
      } else {
        final uoh = await widget.flow.sendToken(
          cfg: widget.cfg,
          keys: widget.keys,
          tokenSymbol: token,
          recipient: to,
          amountWeiLike: amount,
          registry: registry!,
          wantErc2612: usePermit,
          wantPermit2: usePermit2,
          settings: widget.settings,
          ensureAuthorized: widget.authenticate,
          log: (m) => debugPrint(m),
          selectFees: (f) async => f,
        );
        await widget.store.upsertByUserOpHash(uoh, (existing) =>
            existing?.copyWith(status: ActivityStatus.sent) ??
            ActivityItem(
              userOpHash: uoh,
              to: to,
              display: '$amtStr $token',
              ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              status: ActivityStatus.sent,
              chainId: chainId,
              opKind: 'erc20',
              tokenSymbol: token,
              tokenAddress: tokenAddr,
            ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('send error: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _approve() async {
    if (!useEoa || registry == null) return;
    final token = selected;
    final tokenInfo = registry!.token(token)!;
    final decimals = (tokenInfo['decimals'] as num).toInt();
    final amtStr = approveAmtCtrl.text.trim();
    final amount = _parseAmount(amtStr, decimals);
    final spender = spenderCtrl.text.trim();
    final chainId = widget.cfg['chainId'] as int;
    final tokenAddr = registry!.tokenAddress(token, chainId)!;
    if (spender.isEmpty) {
      debugPrint('approve error: missing spender');
      return;
    }
    setState(() => approving = true);
    try {
      final txHash = await widget.eoa.approveToken(
        keys: widget.keys,
        chainId: chainId,
        tokenAddress: tokenAddr,
        spender: spender,
        amount: amount,
      );
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await widget.store.upsertByUserOpHash(txHash, (existing) =>
          existing?.copyWith(status: ActivityStatus.pending, txHash: txHash) ??
          ActivityItem(
            userOpHash: txHash,
            to: spender,
            display: 'Approve $amtStr $token',
            ts: ts,
            status: ActivityStatus.pending,
            chainId: chainId,
            opKind: 'erc20',
            tokenSymbol: token,
            tokenAddress: tokenAddr,
            txHash: txHash,
          ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('approve error: $e');
    } finally {
      if (mounted) setState(() => approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = registry?.raw['tokens'] as List? ?? [];
    final theme = Theme.of(context);
    final permitDisabled = !(registry?.feature(selected, 'erc2612') ?? false);
    final permit2Disabled =
        registry?.permit2Address(widget.cfg['chainId'] as int) == null ||
            !(registry?.feature(selected, 'permit2') ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Send Token')),
      body: registry == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButton<String>(
                    value: selected,
                    items: tokens
                        .map<DropdownMenuItem<String>>((e) => DropdownMenuItem(
                              value: e['symbol'] as String,
                              child: Text(e['symbol'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => selected = v ?? selected),
                  ),
                  const SizedBox(height: 12),
                  ToggleButtons(
                    borderRadius: BorderRadius.circular(16),
                    constraints:
                        const BoxConstraints(minHeight: 36, minWidth: 140),
                    isSelected: [useEoa, !useEoa],
                    onPressed: (index) {
                      setState(() {
                        useEoa = index == 0;
                        if (useEoa) {
                          usePermit = false;
                          usePermit2 = false;
                        }
                      });
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('EOA (raw tx)'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('4337 Smart Wallet'),
                      ),
                    ],
                  ),
                  TextField(
                    controller: toCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Recipient (0x...)'),
                  ),
                  TextField(
                    controller: amtCtrl,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  SwitchListTile(
                    value: usePermit,
                    onChanged: permitDisabled || useEoa
                        ? null
                        : (v) => setState(() => usePermit = v),
                    title: const Text('Use EIP-2612 permit'),
                  ),
                  SwitchListTile(
                    value: usePermit2,
                    onChanged: permit2Disabled || useEoa
                        ? null
                        : (v) => setState(() => usePermit2 = v),
                    title: const Text('Use Permit2'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: sending ? null : _send,
                    child: const Text('Send'),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Token approvals (EOA only)',
                        style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: spenderCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Spender (0x...)'),
                  ),
                  TextField(
                    controller: approveAmtCtrl,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (!useEoa)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Switch to the EOA path to enable raw approvals.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: (!useEoa || approving) ? null : _approve,
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
    );
  }
}
