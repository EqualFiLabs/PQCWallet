import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';

import 'theme/theme.dart';
import 'services/rpc.dart';
import 'services/bundler_client.dart';
import 'crypto/mnemonic.dart';
import 'services/storage.dart';
import 'userop/userop_flow.dart';
import 'state/settings.dart';
import 'ui/settings_screen.dart';

void main() => runApp(const PQCApp());

class PQCApp extends StatefulWidget {
  const PQCApp({super.key});
  @override
  State<PQCApp> createState() => _PQCAppState();
}

class _PQCAppState extends State<PQCApp> {
  late ThemeData _theme;
  Map<String, dynamic>? _cfg;
  final storage = const FlutterSecureStorage();
  KeyMaterial? _keys;
  String _status = 'Ready';
  AppSettings _settings = const AppSettings();
  final SettingsStore _settingsStore = SettingsStore();

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    _load();
  }

  Future<void> _load() async {
    final cfg =
        jsonDecode(await rootBundle.loadString('assets/config.example.json'))
            as Map<String, dynamic>;
    setState(() => _cfg = cfg);
    // Load or create mnemonic
    final existing = await storage.read(key: 'mnemonic');
    final km = deriveFromMnemonic(existing);
    if (existing == null)
      await storage.write(key: 'mnemonic', value: km.mnemonic);
    final s = await _settingsStore.load();
    setState(() {
      _keys = km;
      _settings = s;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SettingsScreen(
              settings: _settings,
              store: _settingsStore,
            )));
    final s = await _settingsStore.load();
    setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('EqualFi PQC Wallet (MVP)'),
          actions: [
            IconButton(
                onPressed: _openSettings, icon: const Icon(Icons.settings))
          ],
        ),
        body: _cfg == null || _keys == null
            ? const Center(child: CircularProgressIndicator())
            : _Body(
                cfg: _cfg!,
                keys: _keys!,
                settings: _settings,
                setStatus: (s) => setState(() => _status = s)),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(12),
          child: Text(_status, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final Map<String, dynamic> cfg;
  final KeyMaterial keys;
  final AppSettings settings;
  final void Function(String) setStatus;
  const _Body({
    required this.cfg,
    required this.keys,
    required this.settings,
    required this.setStatus,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final rpc = RpcClient(widget.cfg['rpcUrl']);
  late final bundler = BundlerClient(widget.cfg['bundlerUrl']);
  final recipientCtl = TextEditingController();
  final amountCtl = TextEditingController(text: '0.001');
  final PendingIndexStore pendingStore = PendingIndexStore();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(child: SelectableText('ChainId: ${widget.cfg['chainId']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('Wallet: ${widget.cfg['walletAddress']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('EntryPoint: ${widget.cfg['entryPoint']}')),
        const SizedBox(height: 8),
        _Card(child: SelectableText('Aggregator: ${widget.cfg['aggregator']}')),
        const SizedBox(height: 8),
        _Card(
            child: SelectableText(
                'ProverRegistry: ${widget.cfg['proverRegistry']}')),
        const SizedBox(height: 8),
        _Card(
            child: SelectableText(
                'ForceOnChainVerify: ${widget.cfg['forceOnChainVerify']}')),
        const SizedBox(height: 16),
        TextField(
            controller: recipientCtl,
            decoration: const InputDecoration(hintText: 'Recipient (0x...)')),
        const SizedBox(height: 8),
        TextField(
            controller: amountCtl,
            decoration: const InputDecoration(hintText: 'Amount ETH')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: _sendEth, child: const Text('Send ETH (PQC)'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: _showPending,
                    child: const Text('Show Pending'))),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton(
                    onPressed: _clearPending,
                    child: const Text('Clear Pending'))),
          ],
        ),
      ],
    );
  }

  Future<void> _sendEth() async {
    try {
      widget.setStatus('Reading wallet state...');
      final wallet = EthereumAddress.fromHex(widget.cfg['walletAddress']);
      final to = EthereumAddress.fromHex(recipientCtl.text.trim());
      final amountWei =
          EtherAmount.fromBase10String(EtherUnit.ether, amountCtl.text.trim())
              .getInWei;

      final flow = UserOpFlow(rpc: rpc, bundler: bundler, store: pendingStore);
      final uoh = await flow.sendEth(
        cfg: widget.cfg,
        keys: widget.keys,
        to: to,
        amountWei: amountWei,
        settings: widget.settings,
        log: widget.setStatus,
      );

      widget.setStatus('Sent. UserOpHash: $uoh (waiting for receipt...)');

      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final r = await bundler.getUserOperationReceipt(uoh);
        if (r != null) {
          await pendingStore.clear(widget.cfg['chainId'], wallet.hex);
          widget
              .setStatus('Inclusion tx: ${r['receipt']['transactionHash']} ✅');
          return;
        }
      }
      widget.setStatus('Timed out waiting for receipt (check explorer).');
    } catch (e) {
      widget.setStatus('Error: $e');
    }
  }

  Future<void> _showPending() async {
    final wallet = EthereumAddress.fromHex(widget.cfg['walletAddress']);
    final chainId = widget.cfg['chainId'];
    final pending = await pendingStore.load(chainId, wallet.hex);
    widget.setStatus(pending == null
        ? 'No pending record'
        : const JsonEncoder.withIndent('  ').convert(pending));
  }

  Future<void> _clearPending() async {
    final wallet = EthereumAddress.fromHex(widget.cfg['walletAddress']);
    final chainId = widget.cfg['chainId'];
    await pendingStore.clear(chainId, wallet.hex);
    widget.setStatus('pendingIndex cleared (canceled by user).');
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0x2211CDEF),
          borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
