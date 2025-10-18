import 'package:flutter/material.dart';
import 'package:reown_walletkit/reown_walletkit.dart';

class WcConnectSheet extends StatelessWidget {
  const WcConnectSheet({
    super.key,
    required this.proposal,
    required this.namespaces,
    required this.onApprove,
    required this.onReject,
    this.busy = false,
  });

  final ProposalData proposal;
  final Map<String, Namespace> namespaces;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = proposal.proposer.metadata;
    final requirements = _buildRequirements(
      proposal: proposal,
      namespaces: namespaces,
    );
    final hasIssues = requirements.any((req) => req.hasIssues);
    final properties = proposal.sessionProperties ?? <String, String>{};
    final accountBadges = _buildAccountBadges(namespaces);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetadataHeader(metadata: metadata),
            if (metadata.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  metadata.description,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (metadata.url.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  metadata.url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            if (accountBadges.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Accounts shared',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: accountBadges,
              ),
            ],
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Requested permissions',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (requirements.isEmpty)
                      _InfoCard(
                        icon: Icons.info_outline,
                        color: theme.colorScheme.primary,
                        message:
                            'This proposal did not include explicit chain requirements.',
                      )
                    else
                      ...requirements
                          .map((req) => _RequirementCard(requirement: req)),
                    if (properties.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Session properties',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _PropertiesCard(properties: properties),
                    ],
                    const SizedBox(height: 16),
                    _ExpiryBanner(expirySeconds: proposal.expiry),
                  ],
                ),
              ),
            ),
            if (hasIssues)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _InfoCard(
                  icon: Icons.shield,
                  color: theme.colorScheme.error,
                  message:
                      'This dApp requests chains or methods your wallet does not support. Review carefully before approving.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onReject,
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: busy || hasIssues ? null : onApprove,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAccountBadges(Map<String, Namespace> namespaces) {
    final badges = <Widget>[];
    final seen = <String>{};
    namespaces.forEach((_, namespace) {
      for (final account in namespace.accounts) {
        if (seen.add(account)) {
          final display =
              account.split(':').isNotEmpty ? account.split(':').last : account;
          badges.add(_ChipLabel(text: display));
        }
      }
    });
    return badges;
  }
}

class _MetadataHeader extends StatelessWidget {
  const _MetadataHeader({required this.metadata});

  final PairingMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconUrl = metadata.icons.isNotEmpty ? metadata.icons.first : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _MetadataIcon(url: iconUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metadata.name.isEmpty ? 'Unknown dApp' : metadata.name,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_moon_outlined,
                    size: 16,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Powered by Reown',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetadataIcon extends StatelessWidget {
  const _MetadataIcon({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = Border.all(
      color: theme.colorScheme.primary.withValues(alpha: 0.4),
    );
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        border: border,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: url == null
            ? Icon(Icons.language, color: theme.colorScheme.primary)
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.language, color: theme.colorScheme.primary),
              ),
      ),
    );
  }
}

class _RequirementCard extends StatelessWidget {
  const _RequirementCard({required this.requirement});

  final _ChainRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = requirement.hasIssues
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _describeChain(requirement.chainId),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _ChipLabel(
                text: requirement.hasIssues ? 'Unsupported' : 'Supported',
                color: statusColor.withValues(alpha: 0.2),
                textColor: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Methods', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          if (requirement.methods.isEmpty)
            Text(
              'No RPC methods were requested.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: requirement.methods
                  .map(
                    (method) => _ChipLabel(
                      text: method,
                      color: requirement.unsupportedMethods.contains(method)
                          ? theme.colorScheme.error.withValues(alpha: 0.18)
                          : theme.colorScheme.primary.withValues(alpha: 0.15),
                      textColor: requirement.unsupportedMethods.contains(method)
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  )
                  .toList(),
            ),
          if (requirement.optionalMethods.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Optional methods', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: requirement.optionalMethods
                  .map((method) => _ChipLabel(text: method))
                  .toList(),
            ),
          ],
          if (requirement.accounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Authorised accounts', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: requirement.accounts
                  .map((account) => _ChipLabel(text: account))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({
    required this.text,
    this.color,
    this.textColor,
  });

  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertiesCard extends StatelessWidget {
  const _PropertiesCard({required this.properties});

  final Map<String, String> properties;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = properties.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    SelectableText(entry.value),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({required this.expirySeconds});

  final int expirySeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(expirySeconds * 1000, isUtc: true)
            .toLocal();
    final formatted = expiry.toLocal().toIso8601String();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: theme.colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Session proposal expires on $formatted',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainRequirement {
  const _ChainRequirement({
    required this.chainId,
    required this.methods,
    required this.optionalMethods,
    required this.unsupportedMethods,
    required this.accounts,
  });

  final String chainId;
  final List<String> methods;
  final List<String> optionalMethods;
  final List<String> unsupportedMethods;
  final List<String> accounts;

  bool get hasIssues => unsupportedMethods.isNotEmpty;
}

List<_ChainRequirement> _buildRequirements({
  required ProposalData proposal,
  required Map<String, Namespace> namespaces,
}) {
  final providedChains = namespaces.isEmpty
      ? <String>{}
      : NamespaceUtils.getChainIdsFromNamespaces(namespaces: namespaces)
          .toSet();
  final providedMethodsByChain = <String, List<String>>{};
  List<String> methodsForChain(String chainId) {
    return providedMethodsByChain.putIfAbsent(
      chainId,
      () => namespaces.isEmpty
          ? <String>[]
          : NamespaceUtils.getNamespacesMethodsForChainId(
              chainId: chainId,
              namespaces: namespaces,
            ),
    );
  }

  final accountsByChain = <String, Set<String>>{};
  namespaces.forEach((nsOrChain, namespace) {
    for (final account in namespace.accounts) {
      final chain = NamespaceUtils.getChainFromAccount(account);
      accountsByChain.putIfAbsent(chain, () => <String>{});
      accountsByChain[chain]!.add(account.split(':').last);
    }
    final chains = NamespaceUtils.getChainIdsFromNamespace(
      nsOrChainId: nsOrChain,
      namespace: namespace,
    );
    for (final chain in chains) {
      accountsByChain.putIfAbsent(chain, () => <String>{});
      for (final account in namespace.accounts) {
        final accountChain = NamespaceUtils.getChainFromAccount(account);
        if (accountChain == chain) {
          accountsByChain[chain]!.add(account.split(':').last);
        }
      }
    }
  });

  final aggregated = <String, _RequirementBuilder>{};
  proposal.requiredNamespaces.forEach((nsOrChain, requiredNamespace) {
    final chains = _resolveRequestedChains(nsOrChain, requiredNamespace);
    for (final chain in chains) {
      final builder = aggregated.putIfAbsent(
        chain,
        () => _RequirementBuilder(
          supported: providedChains.contains(chain),
          providedMethods: methodsForChain(chain),
        ),
      );
      builder.addMethods(requiredNamespace.methods);
    }
  });

  final optional = proposal.optionalNamespaces;
  optional.forEach((nsOrChain, optionalNamespace) {
    final chains = _resolveRequestedChains(nsOrChain, optionalNamespace);
    for (final chain in chains) {
      final builder = aggregated.putIfAbsent(
        chain,
        () => _RequirementBuilder(
          supported: providedChains.contains(chain),
          providedMethods: methodsForChain(chain),
        ),
      );
      builder.addOptional(optionalNamespace.methods);
    }
  });

  final results = aggregated.entries.map((entry) {
    final chain = entry.key;
    final builder = entry.value;
    final accounts = accountsByChain[chain]?.toList() ?? <String>[];
    accounts.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _ChainRequirement(
      chainId: chain,
      methods: builder.methods,
      optionalMethods: builder.optionalMethods,
      unsupportedMethods: builder.unsupportedMethods,
      accounts: accounts,
    );
  }).toList()
    ..sort((a, b) => a.chainId.compareTo(b.chainId));

  return results;
}

class _RequirementBuilder {
  _RequirementBuilder({
    required this.supported,
    required List<String> providedMethods,
  }) : _providedMethods = providedMethods.toSet();

  final bool supported;
  final Set<String> _providedMethods;
  final Set<String> _methods = <String>{};
  final Set<String> _optionalMethods = <String>{};
  final Set<String> _unsupportedMethods = <String>{};

  void addMethods(List<String> methods) {
    for (final method in methods) {
      _methods.add(method);
      if (!_providedMethods.contains(method)) {
        _unsupportedMethods.add(method);
      }
    }
  }

  void addOptional(List<String> methods) {
    _optionalMethods.addAll(methods);
  }

  List<String> get methods {
    final result = _methods.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  List<String> get optionalMethods {
    final result = _optionalMethods.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  List<String> get unsupportedMethods {
    if (supported) {
      final result = _unsupportedMethods.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return result;
    }
    final all = _methods.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return all;
  }
}

List<String> _resolveRequestedChains(
  String nsOrChain,
  RequiredNamespace required,
) {
  final chains = <String>{};
  final explicit = required.chains ?? <String>[];
  chains.addAll(explicit);
  if (NamespaceUtils.isValidChainId(nsOrChain)) {
    chains.add(nsOrChain);
  }
  if (chains.isEmpty) {
    chains.add(nsOrChain);
  }
  return chains.toList();
}

String _describeChain(String chainId) {
  switch (chainId) {
    case 'eip155:8453':
      return 'Base Mainnet (eip155:8453)';
    case 'eip155:84532':
      return 'Base Sepolia (eip155:84532)';
    default:
      return chainId;
  }
}
