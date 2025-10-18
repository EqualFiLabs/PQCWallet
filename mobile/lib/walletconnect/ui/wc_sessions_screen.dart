import 'package:flutter/material.dart';

import '../wc_client.dart';
import '../../utils/address.dart';

class WcSessionsScreen extends StatefulWidget {
  const WcSessionsScreen({super.key, required this.client});

  static const String routeName = '/walletconnect/sessions';

  final WcClient client;

  @override
  State<WcSessionsScreen> createState() => _WcSessionsScreenState();
}

class _WcSessionsScreenState extends State<WcSessionsScreen> {
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_handleClientChanged);
  }

  @override
  void didUpdateWidget(covariant WcSessionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeListener(_handleClientChanged);
      widget.client.addListener(_handleClientChanged);
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_handleClientChanged);
    super.dispose();
  }

  void _handleClientChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _disconnectSession(WcSessionSummary summary) async {
    try {
      await widget.client.disconnect(topic: summary.topic);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnected ${summary.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to disconnect session: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.client.sessionSummaries;
    return Scaffold(
      appBar: AppBar(title: const Text('WalletConnect Sessions')),
      body: sessions.isEmpty
          ? const _EmptySessionsView()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final summary = sessions[index];
                return _SessionTile(
                  summary: summary,
                  onDisconnect: () => _disconnectSession(summary),
                );
              },
            ),
    );
  }
}

class _EmptySessionsView extends StatelessWidget {
  const _EmptySessionsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.satellite_rounded,
                size: 48, color: theme.colorScheme.secondary),
            const SizedBox(height: 16),
            Text(
              'No WalletConnect sessions yet.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a QR code or paste a WalletConnect URI from the home screen to pair with a dApp.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.summary,
    required this.onDisconnect,
  });

  final WcSessionSummary summary;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = summary.accounts
        .map((account) => account.split(':').last)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DappIcon(icons: summary.icons),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.name.isEmpty
                            ? 'Connected dApp'
                            : summary.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (summary.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            summary.description,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (summary.url.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            summary.url,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDisconnect,
                  tooltip: 'Disconnect',
                  icon: const Icon(Icons.link_off_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Accounts',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: accounts
                  .map(
                    (account) => Chip(
                      label: Text(truncateAddress(account)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Expiry',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _formatExpiry(summary.expiry),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpiry(int expirySeconds) {
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(expirySeconds * 1000, isUtc: true)
            .toLocal();
    return expiry.toLocal().toIso8601String();
  }
}

class _DappIcon extends StatelessWidget {
  const _DappIcon({required this.icons});

  final List<String> icons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconUrl = icons.isNotEmpty ? icons.first : null;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
        color: Colors.white10,
      ),
      clipBehavior: Clip.antiAlias,
      child: iconUrl == null
          ? Icon(Icons.language, color: theme.colorScheme.primary)
          : Image.network(
              iconUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.language, color: theme.colorScheme.primary),
            ),
    );
  }
}
