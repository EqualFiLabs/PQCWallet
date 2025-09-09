import 'package:flutter/material.dart';
import '../state/settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final SettingsStore store;
  const SettingsScreen(
      {super.key, required this.settings, required this.store});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  Future<void> _toggle(bool v) async {
    setState(() => _s = _s.copyWith(biometricOnTestnets: v));
    await widget.store.save(_s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Require biometric on testnets'),
            subtitle: const Text(
                'When enabled, you must authenticate before signing on testnets. Always required on mainnet.'),
            value: _s.biometricOnTestnets,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}
