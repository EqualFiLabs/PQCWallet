import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, TextPosition, TextSelection, rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:qr_bar_code_scanner_dialog/qr_bar_code_scanner_dialog.dart';

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
import 'walletconnect/walletconnect.dart';
import 'utils/address.dart';

void main() => runApp(const PQCApp());

enum WalletAccount { eoaClassic, pqcWallet }

class PQCApp extends StatefulWidget {
  const PQCApp({super.key});
  @override
  State<PQCApp> createState() => _PQCAppState();
}

class _PQCAppState extends State<PQCApp> {
  static const String _walletSecretKey = 'mnemonic';
  static const PairingMetadata _wcMetadata = PairingMetadata(
    name: 'EqualFi PQC Wallet',
    description: 'Quantum-safe smart account wallet for Base.',
    url: 'https://equalfi.com',
    icons: <String>[],
  );

  late ThemeData _theme;
  Map<String, dynamic>? _cfg;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final BiometricService _biometric = BiometricService();
  final PinService _pinService = const PinService();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final WcClient _wcClient;
  final WcRouter _wcRouter = const WcRouter();
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
  bool _pairing = false;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    final sessionStore = WcSessionStore(storage: _secureStorage);
    _wcClient = WcClient(
      sessionStore: sessionStore,
      navigatorKey: _navKey,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _wcClient.dispose();
    super.dispose();
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
        final ok = await _biometric.authenticate(reason: reason);
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

    await _initializeWalletConnect(cfg);
  }

  Future<void> _initializeWalletConnect(Map<String, dynamic> cfg) async {
    final wcCfgDynamic = cfg['walletConnect'];
    final wcCfg = wcCfgDynamic is Map<String, dynamic>
        ? wcCfgDynamic
        : <String, dynamic>{};
    final projectId = wcCfg['projectId'] as String?;
    final relayUrl = wcCfg['relayUrl'] as String?;
    final pushUrl = wcCfg['pushUrl'] as String?;

    try {
      await _wcClient.init(
        projectId: projectId,
        metadata: _wcMetadata,
        relayUrl: relayUrl,
        pushUrl: pushUrl,
        logLevel: LogLevel.error,
      );
    } catch (e, st) {
      debugPrint('WalletConnect init failed: $e\n$st');
    }
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
              walletConnectAvailable: _wcClient.isAvailable,
              onOpenWalletConnect: _wcClient.isAvailable
                  ? () => _wcClient.openSessionsScreen()
                  : null,
            )));
    final s = await _settingsStore.load();
    setState(() => _settings = s);
  }

  Future<void> _promptWalletConnectPairing() async {
    final navContext = _navKey.currentContext;
    if (navContext == null) {
      return;
    }
    if (!_wcClient.isAvailable) {
      ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
        const SnackBar(
          content:
              Text('WalletConnect is disabled. Add a project ID in settings.'),
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final scanner = QrBarCodeScannerDialog();
    String? errorText;

    final uriText = await showDialog<String>(
      context: navContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> handleScan() async {
              try {
                await Future<void>.sync(
                  () => scanner.getScannedQrBarCode(
                    context: context,
                    onCode: (value) {
                      if (value == null || value.isEmpty) {
                        return;
                      }
                      final trimmed = value.trim();
                      setDialogState(() {
                        controller.text = trimmed;
                        controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: controller.text.length),
                        );
                        errorText = null;
                      });
                    },
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                  SnackBar(content: Text('QR scan failed: $e')),
                );
              }
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Connect dApp (Reown)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan the QR code or paste the WalletConnect URI shared by the dApp.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'wc:...',
                      errorText: errorText,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          final text = data?.text?.trim() ?? '';
                          if (text.isEmpty) {
                            return;
                          }
                          setDialogState(() {
                            controller.text = text;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                            errorText = null;
                          });
                        },
                      ),
                    ),
                    onChanged: (_) => setDialogState(() => errorText = null),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: handleScan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: controller.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop(controller.text.trim()),
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (uriText == null || uriText.isEmpty) {
      return;
    }

    Uri uri;
    try {
      uri = Uri.parse(uriText);
      if (uri.scheme.toLowerCase() != 'wc') {
        throw const FormatException('Invalid WalletConnect URI');
      }
    } catch (_) {
      ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
        const SnackBar(content: Text('Provide a valid WalletConnect URI.')),
      );
      return;
    }

    setState(() => _pairing = true);
    ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
      const SnackBar(content: Text('Pairing with dApp...')),
    );
    try {
      await _wcClient.pair(uri);
      ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
        const SnackBar(content: Text('WalletConnect pairing started.')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
        SnackBar(content: Text('Failed to pair: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _pairing = false);
      }
    }
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
        _walletSetupError = 'Authentication required to store wallet secret.';
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
          _walletSetupError = 'Authentication required to store wallet secret.';
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

  void _openWalletMenu() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && !scaffold.isDrawerOpen) {
      scaffold.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? pqcWalletAddress =
        _cfg != null ? _cfg!['walletAddress'] as String? : null;
    final String? eoaWalletAddress = _keys?.eoaAddress.hexEip55;
    return MaterialApp(
      navigatorKey: _navKey,
      onGenerateRoute: _wcRouter.onGenerateRoute,
      theme: _theme,
      home: Scaffold(
        key: _scaffoldKey,
        drawer: WalletMenuDrawer(
          selectedAccount: _selectedAccount,
          pqcAddress: pqcWalletAddress,
          eoaAddress: eoaWalletAddress,
          onAccountSelected: (account) {
            _scaffoldKey.currentState?.closeDrawer();
            if (_selectedAccount != account) {
              setState(() => _selectedAccount = account);
            }
          },
        ),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: 0,
          title: Tooltip(
            message: 'Open wallet menu',
            child: InkWell(
              onTap: _openWalletMenu,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _currentWalletTitle(),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _pairing || !_wcClient.isAvailable
                  ? null
                  : _promptWalletConnectPairing,
              tooltip: 'Connect dApp (Reown)',
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner),
                  if (_pairing)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            IconButton(
                onPressed: _openSettings, icon: const Icon(Icons.settings))
          ],
        ),
        body: Column(
          children: [
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.2),
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(child: _buildHomeBody()),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: (index) => setState(() => _selectedNavIndex = index),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.space_dashboard_outlined),
              label: 'Placeholder 1',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'Placeholder 2',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_2),
              label: 'Placeholder 3',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              label: 'Placeholder 4',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz),
              label: 'Placeholder 5',
            ),
          ],
        ),
      ),
    );
  }

  String _currentWalletTitle() {
    final account = _selectedAccount;
    if (account == WalletAccount.pqcWallet) {
      final address = _cfg != null ? _cfg!['walletAddress'] as String? : null;
      return _formatAddressTitle(address);
    }
    final eoaAddress = _keys?.eoaAddress.hexEip55;
    return _formatAddressTitle(eoaAddress);
  }

  String _formatAddressTitle(String? address) {
    if (address == null || address.isEmpty) {
      return 'Wallet';
    }
    return truncateAddress(address);
  }
}

class WalletMenuDrawer extends StatelessWidget {
  const WalletMenuDrawer({
    super.key,
    required this.selectedAccount,
    required this.onAccountSelected,
    this.pqcAddress,
    this.eoaAddress,
  });

  final WalletAccount selectedAccount;
  final ValueChanged<WalletAccount> onAccountSelected;
  final String? pqcAddress;
  final String? eoaAddress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wallet Menu', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Select the active wallet to manage.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _WalletAccountTile(
                    value: WalletAccount.pqcWallet,
                    groupValue: selectedAccount,
                    title: 'PQC Wallet (4337)',
                    address: pqcAddress,
                    onChanged: onAccountSelected,
                  ),
                  _WalletAccountTile(
                    value: WalletAccount.eoaClassic,
                    groupValue: selectedAccount,
                    title: 'EOA (Classic)',
                    address: eoaAddress,
                    onChanged: onAccountSelected,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletAccountTile extends StatelessWidget {
  const _WalletAccountTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.onChanged,
    this.address,
  });

  final WalletAccount value;
  final WalletAccount groupValue;
  final String title;
  final ValueChanged<WalletAccount> onChanged;
  final String? address;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<WalletAccount>(
      value: value,
      groupValue: groupValue,
      onChanged: (wallet) {
        if (wallet != null) {
          onChanged(wallet);
        }
      },
      title: Text(title),
      subtitle: address == null
          ? const Text('Address unavailable')
          : Text(truncateAddress(address!)),
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
    activityPoller =
        ActivityPoller(store: activityStore, rpc: rpc, bundler: bundler);
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
    final accountLabel = isPqc ? 'PQC Wallet (4337)' : 'EOA (Classic)';
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
                    child: Text(isPqc ? 'Send ETH (PQC)' : 'Send ETH (EOA)'))),
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
      await activityStore.upsertByUserOpHash(
          txHash,
          (existing) =>
              existing?.copyWith(
                  status: ActivityStatus.pending, txHash: txHash) ??
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
      widget.setStatus(
          'Switch to the PQC Wallet to send smart-account transactions.');
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

      await activityStore.upsertByUserOpHash(
          uoh,
          (existing) =>
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
