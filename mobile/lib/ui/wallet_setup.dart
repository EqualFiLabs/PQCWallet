import 'package:flutter/material.dart';

class WalletSetupView extends StatelessWidget {
  final VoidCallback onCreateNewWallet;
  final VoidCallback onImportPrivateKey;
  final bool busy;
  final String? errorMessage;

  const WalletSetupView({
    super.key,
    required this.onCreateNewWallet,
    required this.onImportPrivateKey,
    this.busy = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.all(24),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.wallet, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Set up your wallet',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a brand-new EqualFi wallet or import an existing EOA private key.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: busy ? null : onCreateNewWallet,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(busy ? 'Processing...' : 'Create new wallet'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : onImportPrivateKey,
                  icon: const Icon(Icons.key),
                  label: const Text('Import private key'),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    errorMessage!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
