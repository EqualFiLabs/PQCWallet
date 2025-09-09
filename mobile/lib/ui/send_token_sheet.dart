import 'package:flutter/material.dart';
import '../models/token.dart';
import '../userop/userop_flow.dart';
import '../crypto/mnemonic.dart';
import '../state/settings.dart';

class SendTokenSheet extends StatefulWidget {
  final Map<String, dynamic> cfg;
  final UserOpFlow flow;
  final KeyMaterial keys;
  final AppSettings settings;
  const SendTokenSheet({
    super.key,
    required this.cfg,
    required this.flow,
    required this.keys,
    required this.settings,
  });

  @override
  State<SendTokenSheet> createState() => _SendTokenSheetState();
}

class _SendTokenSheetState extends State<SendTokenSheet> {
  ChainTokens? registry;
  String selected = 'USDC';
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  bool usePermit = false;
  bool usePermit2 = false;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    ChainTokens.load().then((r) => setState(() => registry = r));
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
    final amount = _parseAmount(amtCtrl.text.trim(), decimals);
    final to = toCtrl.text.trim();
    setState(() => sending = true);
    try {
      await widget.flow.sendToken(
        cfg: widget.cfg,
        keys: widget.keys,
        tokenSymbol: token,
        recipient: to,
        amountWeiLike: amount,
        registry: registry!,
        wantErc2612: usePermit,
        wantPermit2: usePermit2,
        settings: widget.settings,
        log: (m) => debugPrint(m),
        selectFees: (f) async => f,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('send error: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = registry?.raw['tokens'] as List? ?? [];
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
                    onChanged: permitDisabled
                        ? null
                        : (v) => setState(() => usePermit = v),
                    title: const Text('Use EIP-2612 permit'),
                  ),
                  SwitchListTile(
                    value: usePermit2,
                    onChanged: permit2Disabled
                        ? null
                        : (v) => setState(() => usePermit2 = v),
                    title: const Text('Use Permit2'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: sending ? null : _send,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
    );
  }
}
