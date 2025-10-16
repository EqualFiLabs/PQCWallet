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
import 'services/biometric.dart';
import 'services/ecdsa_key_service.dart';
import 'userop/userop_flow.dart';
import 'state/settings.dart';
import 'ui/settings_screen.dart';
import 'ui/send_sheet.dart';
import 'models/activity.dart';
import 'services/activity_store.dart';
import 'services/activity_poller.dart';
import 'ui/activity_feed.dart';
import 'services/eoa_transactions.dart';
import 'ui/send_token_sheet.dart';

void main() => runApp(const PQCApp());

enum WalletAccount { eoaClassic, pqcWallet }

class PQCApp extends StatefulWidget {
  const PQCApp({super.key});
  @override
  State<PQCApp> createState() => _PQCAppState();
}

class _PQCAppState extends State<PQCApp> {
  late ThemeData _theme;
  Map<String, dynamic>? _cfg;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final BiometricService _biometric = BiometricService();
  KeyMaterial? _keys;
  String _status = 'Ready';
  AppSettings _settings = const AppSettings();
  final SettingsStore _settingsStore = SettingsStore();
  WalletAccount _selectedAccount = WalletAccount.pqcWallet;
  bool _hasUnlockedMnemonic = false;
  bool _unlockFailed = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    _load();
  }

  Future<bool> _authenticateForRead() async {
    final canCheck = await _biometric.canCheck();
    if (!canCheck) {
      return true;
    }
    if (_hasUnlockedMnemonic) {
      return true;
    }
    final ok = await _biometric.authenticate(
        reason: 'Unlock your EqualFi wallet mnemonic');
    if (ok) {
      _hasUnlockedMnemonic = true;
    }
    return ok;
  }

  Future<bool> _authenticateForWrite() async {
    final canCheck = await _biometric.canCheck();
    if (!canCheck) {
      return true;
    }
    return await _biometric.authenticate(
        reason: 'Authorize updating your wallet mnemonic');
  }

  Future<({String? mnemonic, bool authorized})> _readMnemonicProtected() async {
    final allowed = await _authenticateForRead();
    if (!allowed) {
      return (mnemonic: null, authorized: false);
    }
    final value = await _secureStorage.read(key: 'mnemonic');
    return (mnemonic: value, authorized: true);
  }

  Future<bool> _writeMnemonicProtected(String mnemonic) async {
    final allowed = await _authenticateForWrite();
    if (!allowed) {
      return false;
    }
    await _secureStorage.write(key: 'mnemonic', value: mnemonic);
    return true;
  }

  Future<void> _load() async {
    final cfg =
        jsonDecode(await rootBundle.loadString('assets/config.example.json'))
            as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _unlockFailed = false;
      _saveFailed = false;
    });

    final readResult = await _readMnemonicProtected();
    if (!readResult.authorized) {
      if (!mounted) return;
      setState(() {
        _keys = null;
        _unlockFailed = true;
        _status = 'Biometric authentication required to unlock wallet seed.';
      });
      return;
    }

    final km = deriveFromMnemonic(readResult.mnemonic);
    if (readResult.mnemonic == null) {
      final saved = await _writeMnemonicProtected(km.mnemonic);
      if (!saved) {
        if (!mounted) return;
        setState(() {
          _keys = null;
          _saveFailed = true;
          _status = 'Biometric authentication required to store wallet seed.';
        });
        return;
      }
    }

    final s = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _keys = km;
      _settings = s;
      _status = 'Ready';
      _unlockFailed = false;
      _saveFailed = false;
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

  Widget _buildHomeBody() {
    if (_cfg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unlockFailed || _saveFailed) {
      return _LockedView(
        message: _status,
        onRetry: () {
          setState(() {
            _status = 'Ready';
            _hasUnlockedMnemonic = false;
          });
          _load();
        },
      );
    }
    if (_keys == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _Body(
      cfg: _cfg!,
      keys: _keys!,
      settings: _settings,
      selectedAccount: _selectedAccount,
      setStatus: (s) => setState(() => _status = s),
    );
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ToggleButtons(
                constraints: const BoxConstraints(minHeight: 36, minWidth: 140),
                borderRadius: BorderRadius.circular(24),
                isSelected: [
                  _selectedAccount == WalletAccount.eoaClassic,
                  _selectedAccount == WalletAccount.pqcWallet,
                ],
                onPressed: _keys == null
                    ? null
                    : (index) {
                        final selected = index == 0
                            ? WalletAccount.eoaClassic
                            : WalletAccount.pqcWallet;
                        setState(() => _selectedAccount = selected);
                      },
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('EOA (Classic)'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('PQC Wallet'),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: _buildHomeBody(),
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
  final WalletAccount selectedAccount;
  const _Body({
    required this.cfg,
    required this.keys,
    required this.settings,
    required this.setStatus,
    required this.selectedAccount,
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
  final ActivityStore activityStore = ActivityStore();
  late final ActivityPoller activityPoller;
  final ECDSAKeyService _ecdsaService = const ECDSAKeyService();
  late final EOATransactions eoaTx = EOATransactions(rpc: rpc);

  @override
  void initState() {
    super.initState();
    activityStore.load();
    activityPoller = ActivityPoller(store: activityStore, rpc: rpc, bundler: bundler);
    activityPoller.start();
  }

  @override
  void dispose() {
    activityPoller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPqc = widget.selectedAccount == WalletAccount.pqcWallet;
    final accountLabel =
        isPqc ? 'PQC Wallet (4337)' : 'EOA (Classic)';
    final walletAddress = isPqc
        ? widget.cfg['walletAddress'] as String
        : widget.keys.eoaAddress.hexEip55;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(height: 200, child: ActivityFeed(store: activityStore)),
        const SizedBox(height: 16),
        _Card(child: SelectableText('ChainId: ${widget.cfg['chainId']}')),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(accountLabel, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(walletAddress),
            ],
          ),
        ),
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
        if (!isPqc)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '4337 actions are available when the PQC wallet is selected.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: isPqc ? _sendEth : _sendEthEoa,
                    child: Text(
                        isPqc ? 'Send ETH (PQC)' : 'Send ETH (EOA)'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: _openTokenSheet,
                    child: const Text('Token actions'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: isPqc ? _showPending : null,
                    child: const Text('Show Pending'))),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton(
                    onPressed: isPqc ? _clearPending : null,
                    child: const Text('Clear Pending'))),
          ],
        ),
      ],
    );
  }

  Future<void> _openTokenSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SendTokenSheet(
        cfg: widget.cfg,
        flow: UserOpFlow(
          rpc: rpc,
          bundler: bundler,
          store: pendingStore,
          ecdsaService: _ecdsaService,
        ),
        keys: widget.keys,
        settings: widget.settings,
        store: activityStore,
        eoa: eoaTx,
      ),
    );
  }

  Future<void> _sendEthEoa() async {
    final to = recipientCtl.text.trim();
    if (to.isEmpty) {
      widget.setStatus('Recipient required for raw transaction.');
      return;
    }
    final amtStr = amountCtl.text.trim();
    try {
      widget.setStatus('Signing raw transaction...');
      final amountWei =
          EtherAmount.fromBase10String(EtherUnit.ether, amtStr).getInWei;
      final chainId = widget.cfg['chainId'] as int;
      final txHash = await eoaTx.sendEth(
        keys: widget.keys,
        to: to,
        amountWei: amountWei,
        chainId: chainId,
      );
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await activityStore.upsertByUserOpHash(txHash, (existing) =>
          existing?.copyWith(status: ActivityStatus.pending, txHash: txHash) ??
          ActivityItem(
            userOpHash: txHash,
            to: to,
            display: '$amtStr ETH',
            ts: ts,
            status: ActivityStatus.pending,
            chainId: chainId,
            opKind: 'eth',
            txHash: txHash,
          ));
      widget.setStatus('Sent. TxHash: $txHash');
    } catch (e) {
      widget.setStatus('Error: $e');
    }
  }

  Future<void> _sendEth() async {
    if (widget.selectedAccount != WalletAccount.pqcWallet) {
      widget.setStatus('Switch to the PQC Wallet to send smart-account transactions.');
      return;
    }
    try {
      widget.setStatus('Reading wallet state...');
      final wallet = EthereumAddress.fromHex(widget.cfg['walletAddress']);
      final to = EthereumAddress.fromHex(recipientCtl.text.trim());
      final amtStr = amountCtl.text.trim();
      final amountWei =
          EtherAmount.fromBase10String(EtherUnit.ether, amtStr).getInWei;

      final flow = UserOpFlow(
          rpc: rpc,
          bundler: bundler,
          store: pendingStore,
          ecdsaService: _ecdsaService);
      final uoh = await flow.sendEth(
        cfg: widget.cfg,
        keys: widget.keys,
        to: to,
        amountWei: amountWei,
        settings: widget.settings,
        log: widget.setStatus,
        selectFees: (f) => showFeeSheet(context, f),
      );

      await activityStore.upsertByUserOpHash(uoh, (existing) =>
          existing?.copyWith(status: ActivityStatus.sent) ??
          ActivityItem(
            userOpHash: uoh,
            to: to.hex,
            display: '$amtStr ETH',
            ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            status: ActivityStatus.sent,
            chainId: widget.cfg['chainId'],
            opKind: 'eth',
          ));

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

class _LockedView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LockedView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline,
              size: 56, color: theme.colorScheme.secondary),
          const SizedBox(height: 16),
          SizedBox(
            width: 280,
            child: Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry unlock')),
        ],
      ),
    );
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
