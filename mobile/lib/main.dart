import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextPosition, TextSelection, rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:qr_bar_code_scanner_dialog/qr_bar_code_scanner_dialog.dart';
import 'package:web3dart/crypto.dart' as w3;

import 'theme/theme.dart';
import 'services/rpc.dart';
import 'services/bundler_client.dart';
import 'services/app_config.dart';
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
import 'ui/navigation_placeholder_screen.dart';
import 'ui/overview_tab_placeholder.dart';
import 'ui/components/bottom_nav_scaffold.dart';
import 'ui/components/neon_card.dart';
import 'ui/components/top_bar.dart';
import 'walletconnect/walletconnect.dart';
import 'utils/address.dart';
import 'utils/amounts.dart';
import 'utils/config.dart';
import 'services/secure_storage.dart';

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
  static const Set<String> _wcSupportedMethods = <String>{
    'personal_sign',
    'eth_sign',
    'eth_signTypedData',
    'eth_signTypedData_v4',
    'eth_sendTransaction',
    'eth_signTransaction',
  };

  late ThemeData _theme;
  Map<String, dynamic>? _cfg;
  final SecureStorage _secureStorage = SecureStorage.instance;
  final BiometricService _biometric = BiometricService();
  final PinService _pinService = PinService();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final WcClient _wcClient;
  late final WcRouter _wcRouter;
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
  Map<int, WcSigner> _wcSigners = <int, WcSigner>{};
  final Set<String> _registeredWcAccounts = <String>{};
  int? _activeProposalId;
  int? _activeRequestId;
  bool _wcPumpScheduled = false;
  bool _wcHandlingQueue = false;

  @override
  void initState() {
    super.initState();
    _theme = cyberpunkTheme();
    final sessionStore = WcSessionStore(storage: _secureStorage);
    _wcClient = WcClient(sessionStore: sessionStore, navigatorKey: _navKey);
    _wcRouter = WcRouter(client: _wcClient);
    _wcClient.addListener(_handleWalletConnectChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _wcClient.removeListener(_handleWalletConnectChanged);
    _wcClient.dispose();
    super.dispose();
  }

  Future<bool> _ensurePinInitialized() async {
    if (_pinInitialized) return true;
    var hasPin = await _pinService.hasPin();
    while (!hasPin) {
      final navContext = _navKey.currentContext;
      if (navContext == null || !navContext.mounted) {
        return false;
      }
      final messenger = ScaffoldMessenger.maybeOf(navContext);
      final newPin = await showPinSetupDialog(navContext);
      if (newPin == null) {
        return false;
      }
      if (!navContext.mounted) {
        return false;
      }
      await _pinService.setPin(newPin);
      hasPin = true;
      if (!navContext.mounted) {
        return false;
      }
      messenger?.showSnackBar(
        const SnackBar(content: Text('PIN set successfully.')),
      );
    }
    _pinInitialized = true;
    return true;
  }

  Future<bool> _promptForPin(String reason) async {
    final navContext = _navKey.currentContext;
    if (navContext == null || !navContext.mounted) {
      return false;
    }
    final messenger = ScaffoldMessenger.maybeOf(navContext);
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!navContext.mounted) {
        return false;
      }
      final entered = await showPinEntryDialog(
        navContext,
        title: 'Enter wallet PIN',
        helperText: reason,
        errorText: attempt == 0 ? null : 'Incorrect PIN. Try again.',
      );
      if (entered == null) {
        return false;
      }
      if (!navContext.mounted) {
        return false;
      }
      final ok = await _pinService.verify(entered);
      if (ok) {
        return true;
      }
    }
    if (navContext.mounted) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Too many incorrect PIN attempts.')),
      );
    }
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
    final value = await _secureStorage.read(_walletSecretKey);
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
    await _secureStorage.write(_walletSecretKey, encoded);
    return true;
  }

  Future<bool> _authenticateForAction(String reason) async {
    return _authenticate(reason: reason, rememberSession: true);
  }

  Future<void> _load() async {
    final cfg = await _loadAppConfig();
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _settings = settings;
      _unlockFailed = false;
      _saveFailed = false;
    });
    _rebuildWcSigners();

    final readResult = await _readWalletSecretProtected();
    if (!readResult.authorized) {
      if (!mounted) return;
      setState(() {
        _keys = null;
        _wcSigners = <int, WcSigner>{};
        _registeredWcAccounts.clear();
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
        _wcSigners = <int, WcSigner>{};
        _registeredWcAccounts.clear();
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
        _wcSigners = <int, WcSigner>{};
        _registeredWcAccounts.clear();
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
      _registeredWcAccounts.clear();
    });
    _rebuildWcSigners();

    await _initializeWalletConnect(cfg);
  }

  Future<Map<String, dynamic>> _loadAppConfig() async {
    const candidates = <String>[
      'assets/config.json',
      'assets/config.base-sepolia.example.json',
      'assets/config.example.json',
    ];

    for (final asset in candidates) {
      try {
        final jsonStr = await rootBundle.loadString(asset);
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        final normalized = normalizeAppConfig(parsed);
        if (asset != 'assets/config.example.json') {
          debugPrint('Loaded configuration from $asset');
        }
        return normalized;
      } on FlutterError {
        // Asset not found, try the next candidate.
      } on FormatException catch (e) {
        debugPrint('Failed parsing $asset: $e');
      }
    }

    throw StateError(
      'Unable to load configuration. Ensure assets/config.json or config.example.json is available.',
    );
  }

  Future<void> _initializeWalletConnect(Map<String, dynamic> cfg) async {
    final wcCfgDynamic = cfg['walletConnect'];
    final wcCfg = wcCfgDynamic is Map<String, dynamic>
        ? wcCfgDynamic
        : <String, dynamic>{};
    final projectId = (wcCfg['projectId'] as String?)?.trim();
    final relayUrl = wcCfg['relayUrl'] as String?;
    final pushUrl = wcCfg['pushUrl'] as String?;

    if (projectId == null || projectId.isEmpty) {
      debugPrint(
        'WalletConnect disabled: walletConnect.projectId not configured.',
      );
      return;
    }

    try {
      await _wcClient.init(
        projectId: projectId,
        metadata: _wcMetadata,
        relayUrl: relayUrl,
        pushUrl: pushUrl,
        logLevel: LogLevel.error,
      );
      await _registerWalletConnectAccounts();
      _scheduleWalletConnectPump();
    } catch (e, st) {
      debugPrint('WalletConnect init failed: $e\n$st');
    }
  }

  Future<void> _registerWalletConnectAccounts() async {
    if (!_wcClient.isAvailable || !_wcClient.isInitialized) {
      return;
    }
    final cfg = _cfg;
    final keys = _keys;
    if (cfg == null || keys == null) {
      return;
    }
    final chainId = _configChainId(cfg);
    if (chainId == null) {
      return;
    }
    final kit = _wcClient.walletKit;
    if (kit == null) {
      return;
    }
    final account = keys.ecdsa.address.hexEip55;
    final chainLabel = 'eip155:$chainId';
    final registrationKey = '$chainLabel:${account.toLowerCase()}';
    if (_registeredWcAccounts.contains(registrationKey)) {
      return;
    }
    try {
      kit.registerAccount(chainId: chainLabel, accountAddress: account);
      _registeredWcAccounts.add(registrationKey);
    } catch (e) {
      debugPrint('WalletConnect account registration failed: $e');
    }
  }

  void _rebuildWcSigners() {
    final cfg = _cfg;
    final keys = _keys;
    if (cfg == null || keys == null) {
      _wcSigners = <int, WcSigner>{};
      return;
    }
    final chainId = _configChainId(cfg);
    final rpcOverride = _settings.customRpcUrl?.trim();
    final rpcUrl = (rpcOverride != null && rpcOverride.isNotEmpty)
        ? rpcOverride
        : (cfg['rpcUrl'] as String?)?.trim();
    if (chainId == null || rpcUrl == null || rpcUrl.isEmpty) {
      _wcSigners = <int, WcSigner>{};
      return;
    }
    final credentials = EthPrivateKey.fromHex(
      w3.bytesToHex(keys.ecdsa.privateKey, include0x: true),
    );
    final signer = WcSigner(
      credentials: credentials,
      rpcClient: RpcClient(rpcUrl),
      defaultChainId: chainId,
    );
    _wcSigners = <int, WcSigner>{chainId: signer};
  }

  int? _configChainId(Map<String, dynamic>? cfg) {
    if (cfg == null) return null;
    final dynamic value = cfg['chainId'] ?? cfg['chain'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
        return int.tryParse(trimmed.substring(2), radix: 16);
      }
      return int.tryParse(trimmed);
    }
    return null;
  }

  void _handleWalletConnectChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleWalletConnectPump();
  }

  void _scheduleWalletConnectPump() {
    if (_wcPumpScheduled) {
      return;
    }
    if (!_wcClient.isInitialized) {
      return;
    }
    _wcPumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _wcPumpScheduled = false;
      if (!mounted || _wcHandlingQueue) {
        return;
      }
      _wcHandlingQueue = true;
      try {
        await _processWalletConnectQueues();
      } finally {
        _wcHandlingQueue = false;
      }
    });
  }

  Future<void> _processWalletConnectQueues() async {
    while (mounted) {
      if (_activeProposalId != null || _activeRequestId != null) {
        return;
      }
      if (_wcClient.pendingProposals.isNotEmpty) {
        final entry = _wcClient.pendingProposals.entries.first;
        _activeProposalId = entry.key;
        try {
          await _presentProposal(entry.key, entry.value);
        } finally {
          _activeProposalId = null;
        }
        continue;
      }
      if (_wcClient.pendingRequests.isNotEmpty) {
        final entry = _wcClient.pendingRequests.entries.first;
        _activeRequestId = entry.key;
        try {
          await _presentRequest(entry.value);
        } finally {
          _activeRequestId = null;
        }
        continue;
      }
      break;
    }
  }

  Future<void> _presentProposal(int id, ProposalData proposal) async {
    final navContext = _navKey.currentContext;
    if (navContext == null) {
      return;
    }
    final namespaces = _buildNamespacesForProposal(proposal);
    var handled = false;
    await showModalBottomSheet<void>(
      context: navContext,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        var busy = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> approve() async {
              if (busy) return;
              setSheetState(() => busy = true);
              try {
                await _wcClient.approve(
                  id: id,
                  namespaces: namespaces,
                  sessionProperties: proposal.sessionProperties,
                );
                handled = true;
                if (!context.mounted) {
                  return;
                }
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                }
                if (navContext.mounted) {
                  ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        'WalletConnect session approved for ${proposal.proposer.metadata.name.isEmpty ? 'the dApp' : proposal.proposer.metadata.name}.',
                      ),
                    ),
                  );
                }
                await _registerWalletConnectAccounts();
              } catch (e) {
                debugPrint('WalletConnect approve failed: $e');
                if (navContext.mounted) {
                  ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                    SnackBar(content: Text('Failed to approve session: $e')),
                  );
                }
                if (context.mounted) {
                  setSheetState(() => busy = false);
                }
              }
            }

            Future<void> reject() async {
              if (busy) return;
              setSheetState(() => busy = true);
              try {
                await _wcClient.reject(id: id);
                handled = true;
                if (!context.mounted) {
                  return;
                }
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                }
                if (navContext.mounted) {
                  ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                    const SnackBar(
                      content: Text('WalletConnect session rejected.'),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('WalletConnect reject failed: $e');
                if (navContext.mounted) {
                  ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                    SnackBar(content: Text('Failed to reject session: $e')),
                  );
                }
                if (context.mounted) {
                  setSheetState(() => busy = false);
                }
              }
            }

            return WcConnectSheet(
              proposal: proposal,
              namespaces: namespaces,
              busy: busy,
              onApprove: approve,
              onReject: reject,
            );
          },
        );
      },
    );

    if (!handled && mounted && _wcClient.pendingProposals.containsKey(id)) {
      debugPrint('WalletConnect proposal $id remains pending.');
    }
    _scheduleWalletConnectPump();
  }

  Map<String, Namespace> _buildNamespacesForProposal(ProposalData proposal) {
    final keys = _keys;
    if (keys == null || _wcSigners.isEmpty) {
      return <String, Namespace>{};
    }
    final drafts = <String, _NamespaceDraft>{};
    final address = keys.ecdsa.address.hexEip55.toLowerCase();

    void addNamespace(
      String key,
      RequiredNamespace namespace, {
      required bool optional,
    }) {
      final chains = _resolveRequestedChains(key, namespace);
      var hasSupport = false;
      for (final chain in chains) {
        final chainRef = _parseChainReference(chain);
        if (chainRef == null) {
          continue;
        }
        if (!_wcSigners.containsKey(chainRef)) {
          continue;
        }
        hasSupport = true;
        final draft = drafts.putIfAbsent(key, _NamespaceDraft.new);
        draft.chains.add(chain);
        draft.accounts.add('$chain:$address');
      }
      if (!hasSupport) {
        return;
      }
      final draft = drafts.putIfAbsent(key, _NamespaceDraft.new);
      final supportedMethods = namespace.methods.where(
        (method) => _wcSupportedMethods.contains(method),
      );
      draft.methods.addAll(supportedMethods);
      draft.events.addAll(namespace.events);
    }

    proposal.requiredNamespaces.forEach(
      (key, value) => addNamespace(key, value, optional: false),
    );
    proposal.optionalNamespaces.forEach(
      (key, value) => addNamespace(key, value, optional: true),
    );

    return drafts.map((key, draft) {
      final accounts = draft.accounts.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final chains = draft.chains.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final methods = draft.methods.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final events = draft.events.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return MapEntry(
        key,
        Namespace(
          chains: chains,
          accounts: accounts,
          methods: methods,
          events: events,
        ),
      );
    });
  }

  List<String> _resolveRequestedChains(
    String nsOrChain,
    RequiredNamespace namespace,
  ) {
    final chains = <String>{};
    final explicit = namespace.chains ?? <String>[];
    chains.addAll(explicit);
    if (_isValidChainId(nsOrChain)) {
      chains.add(nsOrChain);
    }
    if (chains.isEmpty) {
      chains.add(nsOrChain);
    }
    return chains.toList();
  }

  bool _isValidChainId(String value) {
    final parts = value.split(':');
    return parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty;
  }

  int? _parseChainReference(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    return int.tryParse(parts[1]);
  }

  Future<void> _presentRequest(SessionRequestEvent request) async {
    final navContext = _navKey.currentContext;
    if (navContext == null || !navContext.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(navContext);
    final session = _wcClient.sessions[request.topic];
    if (session == null) {
      final response = JsonRpcResponse<Object?>(
        id: request.id,
        error: const JsonRpcError(code: 4001, message: 'Session not found.'),
      );
      try {
        await _wcClient.respond(topic: request.topic, response: response);
      } catch (e) {
        debugPrint('Failed to respond to missing session: $e');
      }
      return;
    }

    final unsupported = _wcSigners.isEmpty ||
        !await _wcRouter.supports(
          event: request,
          session: session,
          signers: _wcSigners,
        );
    if (!navContext.mounted) {
      return;
    }

    var handled = false;
    await showDialog<void>(
      context: navContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        var busy = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> approve() async {
              if (busy || unsupported) return;
              setDialogState(() => busy = true);
              final chainRef = _parseChainReference(request.chainId);
              if (chainRef != null) {
                final authed = await _ensureWalletConnectAuth(
                  chainId: chainRef,
                  method: request.method,
                  session: session,
                );
                if (!authed) {
                  if (context.mounted) {
                    setDialogState(() => busy = false);
                  }
                  return;
                }
              }
              try {
                final response = await _wcRouter.dispatch(
                  event: request,
                  session: session,
                  signers: _wcSigners,
                );
                await _wcClient.respond(
                  topic: request.topic,
                  response: response,
                );
                handled = true;
                if (!dialogContext.mounted) {
                  return;
                }
                final navigator = Navigator.of(dialogContext);
                if (navigator.canPop()) {
                  navigator.pop();
                }
                if (navContext.mounted) {
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text('${request.method} approved for the dApp.'),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('WalletConnect request failed: $e');
                if (navContext.mounted) {
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text('Failed to handle ${request.method}: $e'),
                    ),
                  );
                }
                if (context.mounted) {
                  setDialogState(() => busy = false);
                }
              }
            }

            Future<void> reject() async {
              if (busy) return;
              setDialogState(() => busy = true);
              final response = JsonRpcResponse<Object?>(
                id: request.id,
                error: const JsonRpcError(
                  code: 4001,
                  message: 'User rejected.',
                ),
              );
              try {
                await _wcClient.respond(
                  topic: request.topic,
                  response: response,
                );
                handled = true;
                if (!dialogContext.mounted) {
                  return;
                }
                final navigator = Navigator.of(dialogContext);
                if (navigator.canPop()) {
                  navigator.pop();
                }
                if (navContext.mounted) {
                  messenger?.showSnackBar(
                    SnackBar(content: Text('${request.method} rejected.')),
                  );
                }
              } catch (e) {
                debugPrint('WalletConnect rejection failed: $e');
                if (navContext.mounted) {
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text('Failed to reject ${request.method}: $e'),
                    ),
                  );
                }
                if (context.mounted) {
                  setDialogState(() => busy = false);
                }
              }
            }

            return WcRequestModal(
              request: request,
              session: session,
              busy: busy,
              unsupported: unsupported,
              onApprove: approve,
              onReject: reject,
            );
          },
        );
      },
    );

    if (!handled &&
        mounted &&
        _wcClient.pendingRequests.containsKey(request.id)) {
      debugPrint('WalletConnect request ${request.id} remains pending.');
    }
    _scheduleWalletConnectPump();
  }

  Future<bool> _ensureWalletConnectAuth({
    required int chainId,
    required String method,
    required SessionData session,
  }) async {
    if (!_settings.requireAuthForChain(chainId)) {
      return true;
    }
    final dappName = session.peer.metadata.name.isEmpty
        ? 'the connected dApp'
        : session.peer.metadata.name;
    final reason =
        'Authenticate to ${method.trim()} on ${_describeChainLabel(chainId)} for $dappName';
    return _authenticateForAction(reason);
  }

  String _describeChainLabel(int chainId) {
    switch (chainId) {
      case 8453:
        return 'Base Mainnet (8453)';
      case 84532:
        return 'Base Sepolia (84532)';
      default:
        return 'chain $chainId';
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
    await nav.push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: _settings,
          store: _settingsStore,
          pinService: _pinService,
          walletConnectAvailable: _wcClient.isAvailable,
          onOpenWalletConnect: _wcClient.isAvailable
              ? () => _wcClient.openSessionsScreen()
              : null,
        ),
      ),
    );
    final s = await _settingsStore.load();
    if (!mounted) return;
    setState(() => _settings = s);
    _rebuildWcSigners();
    _scheduleWalletConnectPump();
  }

  Future<void> _promptWalletConnectPairing() async {
    final navContext = _navKey.currentContext;
    if (navContext == null || !navContext.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(navContext);
    if (!_wcClient.isAvailable) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'WalletConnect is disabled. Add a project ID in settings.',
          ),
        ),
      );
      return;
    }

    final uriText = await showDialog<String>(
      context: navContext,
      builder: (_) => _WalletConnectPairingDialog(parentContext: navContext),
    );
    if (!navContext.mounted) {
      return;
    }
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
      if (navContext.mounted) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Provide a valid WalletConnect URI.')),
        );
      }
      return;
    }

    setState(() => _pairing = true);
    if (navContext.mounted) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Pairing with dApp...')),
      );
    }
    try {
      await _wcClient.pair(uri);
      if (navContext.mounted) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('WalletConnect pairing started.')),
        );
      }
    } catch (e) {
      if (navContext.mounted) {
        messenger?.showSnackBar(SnackBar(content: Text('Failed to pair: $e')));
      }
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
    final saved = await _writeWalletSecretProtected(
      WalletSecret.mnemonic(mnemonic),
    );
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
      _registeredWcAccounts.clear();
    });
    _rebuildWcSigners();
    await _registerWalletConnectAccounts();
    _scheduleWalletConnectPump();
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
        WalletSecret.privateKey(privateKey),
      );
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
        _registeredWcAccounts.clear();
      });
      _rebuildWcSigners();
      await _registerWalletConnectAccounts();
      _scheduleWalletConnectPump();
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
    final effectiveCfg = Map<String, dynamic>.from(_cfg!);
    final customRpc = _settings.customRpcUrl?.trim();
    if (customRpc != null && customRpc.isNotEmpty) {
      effectiveCfg['rpcUrl'] = customRpc;
    }

    final navItems = <NavItem>[
      NavItem(
        icon: Icons.space_dashboard_outlined,
        label: 'Overview',
        builder: (context) => const OverviewTabPlaceholder(),
      ),
      NavItem(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Wallet',
        builder: (context) {
          if (_keys == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final rpcKey = (effectiveCfg['rpcUrl'] as String?) ?? 'rpc-unknown';
          return OverviewScreen(
            key: ValueKey<String>(rpcKey),
            cfg: effectiveCfg,
            keys: _keys!,
            settings: _settings,
            selectedAccount: _selectedAccount,
            setStatus: (s) => setState(() => _status = s),
            authenticate: _authenticateForAction,
          );
        },
      ),
      NavItem(
        icon: Icons.qr_code_2,
        label: 'Placeholder 3',
        builder: (context) => const NavigationPlaceholderScreen(
          icon: Icons.qr_code_2,
          title: 'Placeholder 3',
          message: 'Future PQC tools will appear on this screen.',
        ),
      ),
      NavItem(
        icon: Icons.shield_outlined,
        label: 'Security',
        builder: (context) => _SecurityConfigView(cfg: effectiveCfg),
      ),
      NavItem(
        icon: Icons.upcoming_outlined,
        label: 'Placeholder 4',
        builder: (context) => const NavigationPlaceholderScreen(
          icon: Icons.upcoming_outlined,
          title: 'Placeholder 4',
          message: 'More features are on the way. Thanks for your patience!',
        ),
      ),
    ];

    return BottomNavScaffold(
      currentIndex: _selectedNavIndex,
      onIndexChanged: (index) => setState(() => _selectedNavIndex = index),
      navItems: navItems,
    );
  }

  void _openWalletMenu() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && !scaffold.isDrawerOpen) {
      scaffold.openDrawer();
    }
  }

  TopBarStatus? _deriveTopBarStatus() {
    final normalized = _status.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (lower == 'ready') {
      return TopBarStatus.ready;
    }
    if (lower.contains('error') ||
        lower.contains('fail') ||
        lower.contains('required') ||
        lower.contains('denied')) {
      return TopBarStatus.error;
    }
    return TopBarStatus.syncing;
  }

  Future<void> _copyAddress(String addressText) async {
    final context = _scaffoldKey.currentContext;
    final messenger =
        context != null ? ScaffoldMessenger.maybeOf(context) : null;
    await Clipboard.setData(ClipboardData(text: addressText));
    messenger?.showSnackBar(
      const SnackBar(content: Text('Address copied to clipboard')),
    );
  }

  String? _currentWalletAddressText() {
    final selectedAddress = _selectedAccountAddress();
    if (selectedAddress == null || selectedAddress.isEmpty) {
      return null;
    }
    return truncateAddress(selectedAddress);
  }

  String? _selectedAccountAddress() {
    if (_selectedAccount == WalletAccount.pqcWallet) {
      final address = _cfg != null ? _cfg!['walletAddress'] as String? : null;
      final trimmed = address?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return null;
      }
      return trimmed;
    }
    final eoaAddress = _keys?.eoaAddress.hexEip55;
    final trimmed = eoaAddress?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final String? pqcWalletAddress =
        _cfg != null ? _cfg!['walletAddress'] as String? : null;
    final String? eoaWalletAddress = _keys?.eoaAddress.hexEip55;
    final String? truncatedAddress = _currentWalletAddressText();
    final TopBarStatus? topBarStatus = _deriveTopBarStatus();
    final String? statusText = _status.isNotEmpty ? _status : null;
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
        appBar: TopBar(
          title: _currentWalletTitle(),
          status: topBarStatus,
          statusText: statusText,
          addressText: truncatedAddress,
          onCopy: truncatedAddress != null
              ? () => _copyAddress(truncatedAddress)
              : null,
          onQr: _pairing || !_wcClient.isAvailable
              ? null
              : _promptWalletConnectPairing,
          onSettings: _openSettings,
          onOpenMenu: _openWalletMenu,
          showQrProgress: _pairing,
        ),
        body: _buildHomeBody(),
      ),
    );
  }

  String _currentWalletTitle() {
    return _currentWalletAddressText() ?? 'Wallet';
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
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.4),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _WalletMenuNavIcon(icon: Icons.wallet_outlined),
                      _WalletMenuNavIcon(icon: Icons.key_outlined),
                      _WalletMenuNavIcon(icon: Icons.qr_code_2_outlined),
                      _WalletMenuNavIcon(icon: Icons.settings_outlined),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _NetworkSwitch(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RadioGroup<WalletAccount>(
                groupValue: selectedAccount,
                onChanged: (wallet) {
                  if (wallet != null) {
                    onAccountSelected(wallet);
                  }
                },
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _WalletAccountTile(
                      value: WalletAccount.pqcWallet,
                      title: 'PQC Wallet (4337)',
                      address: pqcAddress,
                    ),
                    _WalletAccountTile(
                      value: WalletAccount.eoaClassic,
                      title: 'EOA (Classic)',
                      address: eoaAddress,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _WalletDrawerFooter(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkSwitch extends StatelessWidget {
  const _NetworkSwitch();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface.withValues(alpha: 0.45);
    const selectedNetwork = 'Base';
    const options = <_NetworkOption>[
      _NetworkOption(
        name: 'Ethereum',
        abbreviation: 'ETH',
        color: Color(0xFF627EEA),
      ),
      _NetworkOption(
        name: 'Base',
        abbreviation: 'BASE',
        color: Color(0xFF0052FF),
      ),
      _NetworkOption(
        name: 'Arbitrum',
        abbreviation: 'ARB',
        color: Color(0xFF28A0F0),
      ),
      _NetworkOption(
        name: 'Optimism',
        abbreviation: 'OP',
        color: Color(0xFFFF0420),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primary.withValues(alpha: 0.5), width: 1.4),
        color: surface,
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Network Switch',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonHideUnderline(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: primary.withValues(alpha: 0.5),
                  width: 1.3,
                ),
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: DropdownButton<String>(
                value: selectedNetwork,
                isExpanded: true,
                borderRadius: BorderRadius.circular(20),
                dropdownColor: theme.colorScheme.surface,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: theme.colorScheme.onSurface,
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  for (final option in options)
                    DropdownMenuItem<String>(
                      value: option.name,
                      child: _NetworkDropdownTile(option: option),
                    ),
                ],
                selectedItemBuilder: (context) {
                  return options
                      .map<Widget>(
                        (option) => Align(
                          alignment: Alignment.centerLeft,
                          child: _NetworkDropdownTile(option: option),
                        ),
                      )
                      .toList();
                },
                onChanged: (_) {},
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a network to change chain ID and RPC.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkOption {
  const _NetworkOption({
    required this.name,
    required this.abbreviation,
    required this.color,
  });

  final String name;
  final String abbreviation;
  final Color color;
}

class _NetworkDropdownTile extends StatelessWidget {
  const _NetworkDropdownTile({required this.option});

  final _NetworkOption option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _NetworkLogo(option: option),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            option.name,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _NetworkLogo extends StatelessWidget {
  const _NetworkLogo({required this.option});

  final _NetworkOption option;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [option.color, option.color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: option.color.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        option.abbreviation,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _WalletMenuNavIcon extends StatelessWidget {
  const _WalletMenuNavIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withValues(alpha: 0.6), width: 1.4),
        color: primary.withValues(alpha: 0.1),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 26, color: primary),
    );
  }
}

class _WalletDrawerFooter extends StatelessWidget {
  const _WalletDrawerFooter();

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const _WalletDrawerLogo(),
            if (version != null && version.isNotEmpty)
              Text(
                'v$version',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WalletDrawerLogo extends StatelessWidget {
  const _WalletDrawerLogo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = LinearGradient(
      colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: gradient,
          ),
          alignment: Alignment.center,
          child: Text(
            'EQ',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'EqualFi',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NamespaceDraft {
  _NamespaceDraft();

  final Set<String> chains = <String>{};
  final Set<String> accounts = <String>{};
  final Set<String> methods = <String>{};
  final Set<String> events = <String>{};
}

class _WalletAccountTile extends StatelessWidget {
  const _WalletAccountTile({
    required this.value,
    required this.title,
    this.address,
  });

  final WalletAccount value;
  final String title;
  final String? address;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<WalletAccount>(
      value: value,
      title: Text(title),
      subtitle: address == null
          ? const Text('Address unavailable')
          : Text(truncateAddress(address!)),
    );
  }
}

class OverviewScreen extends StatefulWidget {
  final Map<String, dynamic> cfg;
  final KeyMaterial keys;
  final AppSettings settings;
  final void Function(String) setStatus;
  final WalletAccount selectedAccount;
  final Future<bool> Function(String reason) authenticate;
  const OverviewScreen({
    super.key,
    required this.cfg,
    required this.keys,
    required this.settings,
    required this.setStatus,
    required this.selectedAccount,
    required this.authenticate,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late final rpc = RpcClient(widget.cfg['rpcUrl']);
  late final bundler = BundlerClient(widget.cfg['bundlerUrl']);
  final recipientCtl = TextEditingController();
  final amountCtl = TextEditingController(text: '0.001');
  final PendingIndexStore pendingStore = PendingIndexStore();
  final ActivityStore activityStore = ActivityStore();
  late final ActivityPoller activityPoller;
  final ECDSAKeyService _ecdsaService = const ECDSAKeyService();
  late final EOATransactions eoaTx = EOATransactions(rpc: rpc);
  bool _loadingBalance = false;
  String _balanceDisplay = '0.00';
  int _balanceRequestId = 0;

  String? get _pqcWalletHex {
    final raw = widget.cfg['walletAddress'] as String?;
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void initState() {
    super.initState();
    activityStore.load();
    activityPoller = ActivityPoller(
      store: activityStore,
      rpc: rpc,
      bundler: bundler,
    );
    activityPoller.start();
    _refreshBalance();
  }

  @override
  void dispose() {
    activityPoller.stop();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldWalletAddress = oldWidget.cfg['walletAddress'] as String?;
    final newWalletAddress = widget.cfg['walletAddress'] as String?;
    if (oldWidget.selectedAccount != widget.selectedAccount ||
        oldWalletAddress != newWalletAddress ||
        oldWidget.keys.eoaAddress != widget.keys.eoaAddress) {
      _refreshBalance();
    }
  }

  String? _currentWalletAddress() {
    if (widget.selectedAccount == WalletAccount.pqcWallet) {
      final pqc = _pqcWalletHex;
      if (pqc == null || pqc.isEmpty) {
        return null;
      }
      return pqc;
    }
    return widget.keys.eoaAddress.hex;
  }

  Future<void> _refreshBalance() async {
    final requestId = ++_balanceRequestId;
    final address = _currentWalletAddress();
    if (address == null) {
      if (mounted && requestId == _balanceRequestId) {
        setState(() {
          _balanceDisplay = '0.00';
          _loadingBalance = false;
        });
      }
      return;
    }
    if (mounted && requestId == _balanceRequestId) {
      setState(() {
        _loadingBalance = true;
      });
    }
    try {
      final result = await rpc.call('eth_getBalance', [address, 'latest']);
      final hex = result?.toString() ?? '0x0';
      final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
      final wei =
          cleaned.isEmpty ? BigInt.zero : BigInt.parse(cleaned, radix: 16);
      final formatted = _formatEthBalance(wei);
      if (mounted && requestId == _balanceRequestId) {
        setState(() {
          _balanceDisplay = formatted;
        });
      }
    } catch (_) {
      if (mounted && requestId == _balanceRequestId) {
        setState(() {
          _balanceDisplay = '0.00';
        });
      }
    } finally {
      if (mounted && requestId == _balanceRequestId) {
        setState(() {
          _loadingBalance = false;
        });
      }
    }
  }

  String _formatEthBalance(BigInt wei) {
    if (wei == BigInt.zero) {
      return '0.00';
    }
    final unit = BigInt.from(10).pow(18);
    final whole = wei ~/ unit;
    final remainder = wei.remainder(unit).toString().padLeft(18, '0');
    final decimals = remainder.substring(0, 5);
    final trimmed = decimals.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.isEmpty) {
      return '${whole.toString()}.00';
    }
    final normalized = trimmed.length == 1 ? '${trimmed}0' : trimmed;
    return '${whole.toString()}.$normalized';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPqc = widget.selectedAccount == WalletAccount.pqcWallet;
    final accountLabel = isPqc ? 'PQC Wallet (4337)' : 'EOA (Classic)';
    final pqcAddressRaw = _pqcWalletHex;
    final isPqcConfigured = pqcAddressRaw != null && pqcAddressRaw.isNotEmpty;
    final walletAddress = isPqc
        ? (isPqcConfigured ? pqcAddressRaw : 'Wallet address not configured')
        : widget.keys.eoaAddress.hexEip55;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: _BalanceHeader(
            balanceText: '$_balanceDisplay ETH',
            loading: _loadingBalance,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(height: 200, child: ActivityFeed(store: activityStore)),
        const SizedBox(height: 16),
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
        if (isPqc && !isPqcConfigured) ...[
          const SizedBox(height: 16),
          _Card(
            child: Text(
              'PQC wallet address not configured. Update assets/config.json with '
              '`walletAddress` to enable smart-account actions.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: recipientCtl,
          decoration: const InputDecoration(hintText: 'Recipient (0x...)'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: amountCtl,
          decoration: const InputDecoration(hintText: 'Amount ETH'),
        ),
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
                onPressed:
                    isPqc ? (isPqcConfigured ? _sendEth : null) : _sendEthEoa,
                child: Text(isPqc ? 'Send ETH (PQC)' : 'Send ETH (EOA)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: isPqc && isPqcConfigured ? _openTokenSheet : null,
                child: const Text('Token actions'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: isPqc && isPqcConfigured ? _showPending : null,
                child: const Text('Show Pending'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: isPqc && isPqcConfigured ? _clearPending : null,
                child: const Text('Clear Pending'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openTokenSheet() async {
    if (_pqcWalletHex == null) {
      widget.setStatus(
        'Configure `walletAddress` in assets/config.json before using token actions.',
      );
      return;
    }
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
      final amountWei = parseDecimalAmount(
        amtStr,
        decimals: 18,
      );
      final chainId = requireChainId(widget.cfg);
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
              status: ActivityStatus.pending,
              txHash: txHash,
            ) ??
            ActivityItem(
              userOpHash: txHash,
              to: to,
              display: '$amtStr ETH',
              ts: ts,
              status: ActivityStatus.pending,
              chainId: chainId,
              opKind: 'eth',
              txHash: txHash,
            ),
      );
      widget.setStatus('Sent. TxHash: $txHash');
    } catch (e) {
      widget.setStatus('Error: $e');
    }
  }

  Future<void> _sendEth() async {
    if (widget.selectedAccount != WalletAccount.pqcWallet) {
      widget.setStatus(
        'Switch to the PQC Wallet to send smart-account transactions.',
      );
      return;
    }
    final walletHex = _pqcWalletHex;
    if (walletHex == null) {
      widget.setStatus(
        'Configure `walletAddress` in assets/config.json before sending from the PQC wallet.',
      );
      return;
    }
    try {
      widget.setStatus('Reading wallet state...');
      final wallet = EthereumAddress.fromHex(walletHex);
      final to = EthereumAddress.fromHex(recipientCtl.text.trim());
      final amtStr = amountCtl.text.trim();
      final amountWei = parseDecimalAmount(
        amtStr,
        decimals: 18,
      );
      final chainId = requireChainId(widget.cfg);

      final flow = UserOpFlow(
        rpc: rpc,
        bundler: bundler,
        store: pendingStore,
        ecdsaService: _ecdsaService,
      );
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
              chainId: chainId,
              opKind: 'eth',
            ),
      );

      widget.setStatus('Sent. UserOpHash: $uoh (waiting for receipt...)');

      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final r = await bundler.getUserOperationReceipt(uoh);
        if (r != null) {
          await pendingStore.clear(chainId, wallet.hex);
          widget.setStatus(
            'Inclusion tx: ${r['receipt']['transactionHash']} ✅',
          );
          return;
        }
      }
      widget.setStatus('Timed out waiting for receipt (check explorer).');
    } catch (e) {
      widget.setStatus('Error: $e');
    }
  }

  Future<void> _showPending() async {
    final walletHex = _pqcWalletHex;
    if (walletHex == null) {
      widget.setStatus(
        'Configure `walletAddress` in assets/config.json before checking pending operations.',
      );
      return;
    }
    final wallet = EthereumAddress.fromHex(walletHex);
    final chainId = parseChainId(widget.cfg['chainId']);
    if (chainId == null) {
      widget.setStatus('Config missing chainId; unable to read pending ops.');
      return;
    }
    final pending = await pendingStore.load(chainId, wallet.hex);
    widget.setStatus(
      pending == null
          ? 'No pending record'
          : const JsonEncoder.withIndent('  ').convert(pending),
    );
  }

  Future<void> _clearPending() async {
    final walletHex = _pqcWalletHex;
    if (walletHex == null) {
      widget.setStatus(
        'Configure `walletAddress` in assets/config.json before clearing pending operations.',
      );
      return;
    }
    final wallet = EthereumAddress.fromHex(walletHex);
    final chainId = parseChainId(widget.cfg['chainId']);
    if (chainId == null) {
      widget.setStatus('Config missing chainId; unable to clear pending ops.');
      return;
    }
    await pendingStore.clear(chainId, wallet.hex);
    widget.setStatus('pendingIndex cleared (canceled by user).');
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balanceText, required this.loading});

  final String balanceText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        theme.textTheme.displaySmall ?? theme.textTheme.headlineMedium;
    final textStyle = baseStyle?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(balanceText, style: textStyle),
        if (loading) ...[
          const SizedBox(height: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}

class _WalletConnectPairingDialog extends StatefulWidget {
  const _WalletConnectPairingDialog({required this.parentContext});

  final BuildContext parentContext;

  @override
  State<_WalletConnectPairingDialog> createState() =>
      _WalletConnectPairingDialogState();
}

class _WalletConnectPairingDialogState
    extends State<_WalletConnectPairingDialog> {
  late final TextEditingController _controller;
  final QrBarCodeScannerDialog _scanner = QrBarCodeScannerDialog();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleScan() async {
    try {
      await Future<void>.sync(
        () => _scanner.getScannedQrBarCode(
          context: context,
          onCode: (value) {
            if (!mounted || value == null) {
              return;
            }
            final trimmed = value.trim();
            if (trimmed.isEmpty) {
              return;
            }
            setState(() {
              _controller.text = trimmed;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
              _errorText = null;
            });
          },
        ),
      );
    } catch (e) {
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.maybeOf(
          widget.parentContext,
        )?.showSnackBar(SnackBar(content: Text('QR scan failed: $e')));
      }
    }
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _errorText = null;
    });
  }

  void _handleChanged(String _) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  bool get _hasInput => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'wc:...',
              errorText: _errorText,
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: _handlePaste,
              ),
            ),
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _handleScan,
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
          onPressed: _hasInput
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

class _SecurityConfigView extends StatelessWidget {
  const _SecurityConfigView({required this.cfg});
  final Map<String, dynamic> cfg;

  String _fmt(Object? v) =>
      (v == null || (v is String && v.isEmpty)) ? 'Not set' : v.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Security & Network', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        NeonCard(child: SelectableText('ChainID: ${_fmt(cfg['chainId'])}')),
        const SizedBox(height: 8),
        NeonCard(
          child: SelectableText('EntryPoint: ${_fmt(cfg['entryPoint'])}'),
        ),
        const SizedBox(height: 8),
        NeonCard(
          child: SelectableText('Aggregator: ${_fmt(cfg['aggregator'])}'),
        ),
        const SizedBox(height: 8),
        NeonCard(
          child: SelectableText(
            'ProverRegistry: ${_fmt(cfg['proverRegistry'])}',
          ),
        ),
        const SizedBox(height: 8),
        NeonCard(
          child: SelectableText(
            'ForceOnChainVerify: ${_fmt(cfg['forceOnChainVerify'])}',
          ),
        ),
        const SizedBox(height: 8),
        NeonCard(child: SelectableText('RPC: ${_fmt(cfg['rpcUrl'])}')),
        const SizedBox(height: 8),
        NeonCard(child: SelectableText('Bundler: ${_fmt(cfg['bundlerUrl'])}')),
      ],
    );
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
          Icon(
            Icons.lock_outline,
            size: 56,
            color: theme.colorScheme.secondary,
          ),
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
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}
