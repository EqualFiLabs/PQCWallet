import 'package:flutter/material.dart';

import '../services/biometric.dart';
import '../services/pin_service.dart';
import '../state/settings.dart';
import 'dialogs/pin_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final SettingsStore store;
  final PinService pinService;
  const SettingsScreen(
      {super.key,
      required this.settings,
      required this.store,
      required this.pinService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;
  bool _checkingBiometric = false;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
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
    if (!can) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Biometric authentication is not available on this device.')));
      }
      setState(() => _checkingBiometric = false);
      return;
    }
    final ok = await bio.authenticate(reason: 'Enable biometric authentication');
    setState(() => _checkingBiometric = false);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Biometric authentication canceled.')));
      }
      return;
    }
    setState(() => _s = _s.copyWith(useBiometric: true));
    await widget.store.save(_s);
  }

  Future<bool> _verifyCurrentPin() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final entered = await showPinEntryDialog(
        context,
        title: 'Enter current PIN',
        errorText:
            attempt == 0 ? null : 'Incorrect PIN. Please try again.',
      );
      if (entered == null) {
        return false;
      }
      final ok = await widget.pinService.verify(entered);
      if (ok) return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Authentication failed after multiple attempts.')));
    }
    return false;
  }

  Future<void> _changePin() async {
    final hasPin = await widget.pinService.hasPin();
    if (hasPin) {
      final ok = await _verifyCurrentPin();
      if (!ok) return;
    }
    final newPin = await showPinSetupDialog(context);
    if (newPin == null) return;
    await widget.pinService.setPin(newPin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN updated.')));
    }
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
        ],
      ),
    );
  }
}
