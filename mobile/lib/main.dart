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
import 'services/wallet_secret.dart';
import 'services/pin_service.dart';
import 'userop/userop_flow.dart';
import 'state/settings.dart';
import 'ui/dialogs/pin_dialog.dart';
import 'ui/dialogs/import_private_key_dialog.dart';
import 'ui/settings_screen.dart';
import 'ui/send_sheet.dart';
import 'models/activity.dart';
import 'services/activity_store.dart';
import 'services/activity_poller.dart';
import 'ui/activity_feed.dart';
import 'services/eoa_transactions.dart';
import 'ui/send_token_sheet.dart';
import 'ui/wallet_setup.dart';

void main() => runApp(const PQCApp());

enum WalletAccount { eoaClassic, pqcWallet }

class PQCApp extends StatefulWidget {
  const PQCApp({super.key});
  @override
  State<PQCApp> createState() => _PQCAppState();
}

class _PQCAppState extends State<PQCApp> {
  static const String _walletSecretKey = 'mnemonic';

  late ThemeData _theme;
  Map<String, dynamic>? _cfg;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final BiometricService _biometric = BiometricService();
  final PinService _pinService = const PinService();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  KeyMaterial? _keys;
  String _status = 'Ready';
  AppSettings _settings = const AppSettings();
  final SettingsStore _settingsStore = SettingsStore();
  WalletAccount _selectedAccount = WalletAccount.pqcWallet;
  bool _hasUnlockedMnemonic = false;
  bool _unlockFailed = false;
  bool _saveFailed = false;
  bool _pinInitialized = false;
  bool _needsWalletSetup = false;
  bool _walletSetupBusy = false;
  String? _walletSetupError;

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<bool> _ensurePinInitialized() async {
    if (_pinInitialized) return true;
    var hasPin = await _pinService.hasPin();
    while (!hasPin) {
      final navContext = _navKey.currentContext;
      if (!mounted || navContext == null) {
        return false;
      }
      final newPin = await showPinSetupDialog(navContext);
      if (newPin == null) {
        return false;
      }
      await _pinService.setPin(newPin);
      hasPin = true;
      ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
        const SnackBar(content: Text('PIN set successfully.')),
      );
    }
    _pinInitialized = true;
    return true;
  }

  Future<bool> _promptForPin(String reason) async {
    final navContext = _navKey.currentContext;
    if (!mounted || navContext == null) {
      return false;
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final entered = await showPinEntryDialog(
        navContext,
        title: 'Enter wallet PIN',
        helperText: reason,
        errorText: attempt == 0 ? null : 'Incorrect PIN. Try again.',
      );
      if (entered == null) {
        return false;
      }
      final ok = await _pinService.verify(entered);
      if (ok) {
        return true;
      }
    }
    ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
      const SnackBar(content: Text('Too many incorrect PIN attempts.')),
    );
    return false;
  }

  Future<bool> _authenticate({
    required String reason,
    bool rememberSession = false,
  }) async {
    final ready = await _ensurePinInitialized();
    if (!ready) return false;

    if (_settings.useBiometric) {
      final canCheck = await _biometric.canCheck();
      if (canCheck) {
        final ok =
            await _biometric.authenticate(reason: reason);
        if (ok) {
          if (rememberSession) {
            _hasUnlockedMnemonic = true;
          }
          return true;
        }
      }
    }

    final ok = await _promptForPin(reason);
    if (ok && rememberSession) {
      _hasUnlockedMnemonic = true;
    }
    return ok;
  }

  Future<bool> _authenticateForRead() async {
    if (_hasUnlockedMnemonic) {
      return true;
    }
    return _authenticate(
      reason: 'Unlock your EqualFi wallet secret',
      rememberSession: true,
    );
  }

  Future<bool> _authenticateForWrite() {
    return _authenticate(
      reason: 'Authorize updating your wallet secret',
      rememberSession: true,
    );
  }

  Future<({WalletSecret? secret, bool authorized, bool hadCorruptData})>
      _readWalletSecretProtected() async {
    final allowed = await _authenticateForRead();
    if (!allowed) {
      return (secret: null, authorized: false, hadCorruptData: false);
    }
    final value = await _secureStorage.read(key: _walletSecretKey);
    if (value == null) {
      return (secret: null, authorized: true, hadCorruptData: false);
    }
    try {
      final secret = WalletSecretCodec.decode(value);
      return (secret: secret, authorized: true, hadCorruptData: false);
    } on ArgumentError {
      return (secret: null, authorized: true, hadCorruptData: true);
    }
  }

  Future<bool> _writeWalletSecretProtected(WalletSecret secret) async {
    final allowed = await _authenticateForWrite();
    if (!allowed) {
      return false;
    }
    final encoded = WalletSecretCodec.encode(secret);
    await _secureStorage.write(key: _walletSecretKey, value: encoded);
    return true;
  }

  Future<bool> _authenticateForAction(String reason) async {
    return _authenticate(reason: reason, rememberSession: true);
  }

  Future<void> _load() async {
    final cfg =
        jsonDecode(await rootBundle.loadString('assets/config.example.json'))
            as Map<String, dynamic>;
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _settings = settings;
      _unlockFailed = false;
      _saveFailed = false;
    });

    final readResult = await _readWalletSecretProtected();
    if (!readResult.authorized) {
      if (!mounted) return;
      setState(() {
        _keys = null;
        _unlockFailed = true;
        _status = 'Authentication required to unlock wallet secret.';
        _needsWalletSetup = false;
        _walletSetupBusy = false;
        _walletSetupError = null;
      });
      return;
    }

    if (readResult.secret == null) {
      if (!mounted) return;
      setState(() {
        _keys = null;
        _needsWalletSetup = true;
        _walletSetupBusy = false;
        _walletSetupError = readResult.hadCorruptData
            ? 'Stored wallet secret was invalid. Please set up your wallet again.'
            : null;
        _status = 'Wallet setup required.';
      });
      return;
    }

    KeyMaterial km;
    try {
      km = _deriveKeyMaterialFromSecret(readResult.secret!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _keys = null;
        _needsWalletSetup = true;
        _walletSetupBusy = false;
        _walletSetupError = 'Failed to load wallet: $e';
        _status = 'Wallet setup required.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _keys = km;
      _status = 'Ready';
      _unlockFailed = false;
      _saveFailed = false;
      _needsWalletSetup = false;
      _walletSetupBusy = false;
      _walletSetupError = null;
    });
  }

  KeyMaterial _deriveKeyMaterialFromSecret(WalletSecret secret) {
    switch (secret.type) {
      case WalletSecretType.mnemonic:
        return deriveFromMnemonic(secret.value);
      case WalletSecretType.privateKey:
        return deriveFromPrivateKey(secret.value);
    }
  }

  Future<void> _openSettings() async {
    final nav = _navKey.currentState;
    final navContext = _navKey.currentContext;
    if (nav == null || navContext == null) return;
    await nav.push(MaterialPageRoute(
        builder: (_) => SettingsScreen(
              settings: _settings,
              store: _settingsStore,
              pinService: _pinService,
            )));
    final s = await _settingsStore.load();
    setState(() => _settings = s);
  }

  Future<void> _handleCreateNewWallet() async {
    setState(() {
      _walletSetupBusy = true;
      _walletSetupError = null;
      _status = 'Generating new wallet...';
    });
    final km = deriveFromMnemonic(null);
    final mnemonic = km.mnemonic;
    if (mnemonic == null) {
      if (!mounted) return;
      setState(() {
        _walletSetupBusy = false;
        _walletSetupError = 'Failed to derive mnemonic.';
        _status = 'Wallet setup required.';
      });
      return;
    }
    final saved =
        await _writeWalletSecretProtected(WalletSecret.mnemonic(mnemonic));
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _walletSetupBusy = false;
        _walletSetupError =
            'Authentication required to store wallet secret.';
        _status = 'Wallet setup required.';
      });
      return;
    }
    setState(() {
      _keys = km;
      _status = 'Ready';
      _needsWalletSetup = false;
      _walletSetupBusy = false;
      _walletSetupError = null;
      _unlockFailed = false;
      _saveFailed = false;
    });
  }

  Future<void> _handleImportPrivateKey() async {
    final navContext = _navKey.currentContext;
    if (navContext == null) {
      return;
    }
    setState(() {
      _walletSetupBusy = true;
      _walletSetupError = null;
      _status = 'Waiting for private key...';
    });
    final privateKey = await showImportPrivateKeyDialog(navContext);
    if (!mounted) return;
    if (privateKey == null) {
      setState(() {
        _walletSetupBusy = false;
        _status = 'Wallet setup required.';
      });
      return;
    }
    try {
      final km = deriveFromPrivateKey(privateKey);
      final saved = await _writeWalletSecretProtected(
          WalletSecret.privateKey(privateKey));
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _walletSetupBusy = false;
          _walletSetupError =
              'Authentication required to store wallet secret.';
          _status = 'Wallet setup required.';
        });
        return;
      }
      setState(() {
        _keys = km;
        _status = 'Ready';
        _needsWalletSetup = false;
        _walletSetupBusy = false;
        _walletSetupError = null;
        _unlockFailed = false;
        _saveFailed = false;
      });
    } on ArgumentError catch (e) {
      final message = e.message ?? e.toString();
      setState(() {
        _walletSetupBusy = false;
        _walletSetupError = message.toString();
        _status = 'Wallet setup required.';
      });
    } catch (e) {
      setState(() {
        _walletSetupBusy = false;
        _walletSetupError = 'Failed to import key: $e';
        _status = 'Wallet setup required.';
      });
    }
  }

  Widget _buildHomeBody() {
    if (_cfg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_needsWalletSetup) {
      return WalletSetupView(
        busy: _walletSetupBusy,
        errorMessage: _walletSetupError,
        onCreateNewWallet: () => _handleCreateNewWallet(),
        onImportPrivateKey: () => _handleImportPrivateKey(),
      );
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
    final effectiveCfg = Map<String, dynamic>.from(_cfg!);
    final customRpc = _settings.customRpcUrl?.trim();
    if (customRpc != null && customRpc.isNotEmpty) {
      effectiveCfg['rpcUrl'] = customRpc;
    }
    return _Body(
      key: ValueKey<String>(effectiveCfg['rpcUrl'] as String),
      cfg: effectiveCfg,
      keys: _keys!,
      settings: _settings,
      selectedAccount: _selectedAccount,
      setStatus: (s) => setState(() => _status = s),
      authenticate: _authenticateForAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
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
  final Future<bool> Function(String reason) authenticate;
  const _Body({
    super.key,
    required this.cfg,
    required this.keys,
    required this.settings,
    required this.setStatus,
    required this.selectedAccount,
    required this.authenticate,
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
        authenticate: widget.authenticate,
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
        ensureAuthorized: widget.authenticate,
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
