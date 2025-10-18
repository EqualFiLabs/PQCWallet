import 'package:flutter/material.dart';

import '../../services/wallet_secret.dart';

Future<String?> showImportPrivateKeyDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ImportPrivateKeyDialog(),
  );
}

class _ImportPrivateKeyDialog extends StatefulWidget {
  const _ImportPrivateKeyDialog();

  @override
  State<_ImportPrivateKeyDialog> createState() => _ImportPrivateKeyDialogState();
}

class _ImportPrivateKeyDialogState extends State<_ImportPrivateKeyDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final input = _controller.text;
    try {
      final normalized = normalizePrivateKeyHex(input);
      Navigator.of(context).pop(normalized);
    } on ArgumentError catch (e) {
      final message = e.message ?? e.toString();
      setState(() => _error = message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import private key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Paste the 32-byte hex private key (without spacing). '
            'This will be stored securely on this device.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: '0x...',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscure = !_obscure),
              ),
            ),
            keyboardType: TextInputType.visiblePassword,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _validateAndSubmit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}
