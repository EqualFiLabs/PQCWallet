import 'package:flutter/material.dart';

import '../services/biometric.dart';
import '../services/pin_service.dart';
import '../state/settings.dart';
import 'dialogs/pin_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final SettingsStore store;
  final PinService pinService;
  final bool walletConnectAvailable;
  final VoidCallback? onOpenWalletConnect;
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.store,
    required this.pinService,
    this.walletConnectAvailable = false,
    this.onOpenWalletConnect,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;
  bool _checkingBiometric = false;
  late TextEditingController _rpcController;
  String? _rpcError;
  bool _savingRpc = false;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _rpcController = TextEditingController(text: _s.customRpcUrl ?? '');
    _rpcController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _rpcController.dispose();
    super.dispose();
  }

  Future<void> _toggleBiometricForTestnets(bool v) async {
    setState(() => _s = _s.copyWith(biometricOnTestnets: v));
    await widget.store.save(_s);
  }

  Future<void> _toggleUseBiometric(bool v) async {
    if (v == _s.useBiometric) return;
    if (!v) {
      setState(() => _s = _s.copyWith(useBiometric: false));
      await widget.store.save(_s);
      return;
    }

    setState(() => _checkingBiometric = true);
    final bio = BiometricService();
    final can = await bio.canCheck();
    if (!mounted) {
      return;
    }
    if (!can) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Biometric authentication is not available on this device.')));
      setState(() => _checkingBiometric = false);
      return;
    }
    final ok = await bio.authenticate(reason: 'Enable biometric authentication');
    if (!mounted) {
      return;
    }
    setState(() => _checkingBiometric = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication canceled.')));
      return;
    }
    setState(() => _s = _s.copyWith(useBiometric: true));
    await widget.store.save(_s);
  }

  Future<bool> _verifyCurrentPin() async {
    final currentContext = context;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!currentContext.mounted) {
        return false;
      }
      final entered = await showPinEntryDialog(
        currentContext,
        title: 'Enter current PIN',
        errorText:
            attempt == 0 ? null : 'Incorrect PIN. Please try again.',
      );
      if (entered == null) {
        return false;
      }
      if (!currentContext.mounted) {
        return false;
      }
      final ok = await widget.pinService.verify(entered);
      if (ok) return true;
    }
    if (currentContext.mounted) {
      ScaffoldMessenger.of(currentContext).showSnackBar(const SnackBar(
          content: Text('Authentication failed after multiple attempts.')));
    }
    return false;
  }

  Future<void> _changePin() async {
    final currentContext = context;
    final hasPin = await widget.pinService.hasPin();
    if (hasPin) {
      final ok = await _verifyCurrentPin();
      if (!ok) return;
    }
    if (!currentContext.mounted) return;
    final newPin = await showPinSetupDialog(currentContext);
    if (!currentContext.mounted) return;
    if (newPin == null) return;
    await widget.pinService.setPin(newPin);
    if (currentContext.mounted) {
      ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text('PIN updated.')));
    }
  }

  Future<void> _saveCustomRpcOverride() async {
    final input = _rpcController.text.trim();
    if (input.isNotEmpty) {
      final parsed = Uri.tryParse(input);
      if (parsed == null ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        setState(() => _rpcError = 'Enter a valid http(s) endpoint.');
        return;
      }
    }
    setState(() {
      _savingRpc = true;
      _rpcError = null;
      _s = _s.copyWith(customRpcUrl: input.isEmpty ? null : input);
    });
    await widget.store.save(_s);
    if (!mounted) return;
    setState(() => _savingRpc = false);
    final message = input.isEmpty
        ? 'RPC reset to bundled config.'
        : 'Custom RPC endpoint saved.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Use biometrics when available'),
            subtitle: const Text(
                'When enabled, you can authenticate with Face/Touch ID. PIN unlock remains available as fallback.'),
            value: _s.useBiometric,
            onChanged: _checkingBiometric ? null : _toggleUseBiometric,
          ),
          SwitchListTile(
            title: const Text('Require biometric on testnets'),
            subtitle: const Text(
                'When enabled, you must authenticate before signing on testnets. Always required on mainnet.'),
            value: _s.biometricOnTestnets,
            onChanged: _s.useBiometric ? _toggleBiometricForTestnets : null,
          ),
          ListTile(
            title: const Text('Change wallet PIN'),
            subtitle: const Text('Default unlock method.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePin,
          ),
          ListTile(
            title: const Text('WalletConnect'),
            subtitle: Text(
              widget.walletConnectAvailable
                  ? 'Manage connected dapps and pair new sessions.'
                  : 'Provide a WalletConnect Project ID to enable.',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: widget.walletConnectAvailable &&
                widget.onOpenWalletConnect != null,
            onTap: widget.onOpenWalletConnect == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    Future.microtask(
                        () => widget.onOpenWalletConnect?.call());
                  },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Network',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _rpcController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Custom RPC endpoint',
                hintText: 'https://base-sepolia.example',
                helperText:
                    'Leave blank to use the bundled Base config.',
                errorText: _rpcError,
                suffixIcon: _rpcController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _savingRpc
                            ? null
                            : () {
                                _rpcController.clear();
                                setState(() => _rpcError = null);
                              },
                      ),
              ),
              onChanged: (_) => setState(() => _rpcError = null),
              onSubmitted: (_) => _saveCustomRpcOverride(),
              enabled: !_savingRpc,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: _savingRpc ? null : _saveCustomRpcOverride,
              icon: Icon(
                _rpcController.text.trim().isEmpty
                    ? Icons.replay
                    : Icons.save,
              ),
              label: Text(
                _rpcController.text.trim().isEmpty
                    ? 'Use default RPC'
                    : 'Save RPC override',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
