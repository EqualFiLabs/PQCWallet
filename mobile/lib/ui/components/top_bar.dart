import 'package:flutter/material.dart';

enum TopBarStatus { ready, syncing, error }

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({
    super.key,
    this.title,
    this.status,
    this.statusText,
    this.addressText,
    this.onCopy,
    this.onQr,
    this.onSettings,
    this.onOpenMenu,
    this.showQrProgress = false,
  });

  final Object? title;
  final TopBarStatus? status;
  final String? statusText;
  final String? addressText;
  final VoidCallback? onCopy;
  final VoidCallback? onQr;
  final VoidCallback? onSettings;
  final VoidCallback? onOpenMenu;
  final bool showQrProgress;

  bool get _hasStatusText =>
      statusText != null && statusText!.trim().isNotEmpty;

  @override
  Size get preferredSize {
    if (_hasStatusText) {
      return const Size.fromHeight(kToolbarHeight + 40);
    }
    return const Size.fromHeight(kToolbarHeight);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Widget> actions = <Widget>[
      IconButton(
        tooltip: 'Connect dApp (Reown)',
        onPressed: onQr,
        icon: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.qr_code_scanner),
            if (showQrProgress)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: onSettings,
        icon: const Icon(Icons.settings),
      ),
    ];

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 0,
      title: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Open wallet menu',
              child: InkWell(
                onTap: onOpenMenu,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined),
                      const SizedBox(width: 6),
                      Expanded(child: _buildTitleContent(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onCopy != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                tooltip:
                    addressText != null ? 'Copy $addressText' : 'Copy address',
                onPressed: onCopy,
                icon: const Icon(Icons.copy),
              ),
            ),
          if (status != null && status != TopBarStatus.ready)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _StatusChip(status: status!),
                ),
              ),
            ),
        ],
      ),
      actions: actions,
      bottom: _hasStatusText
          ? PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.2,
                ),
                child: Text(
                  statusText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTitleContent(BuildContext context) {
    final value = title;
    if (value == null) {
      return const SizedBox.shrink();
    }
    if (value is Widget) {
      return value;
    }
    if (value is String) {
      return Text(value, overflow: TextOverflow.ellipsis, softWrap: false);
    }
    return Text(
      value.toString(),
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TopBarStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    late final Color textColor;
    late final Color backgroundColor;
    late final IconData icon;
    late final String label;

    switch (status) {
      case TopBarStatus.ready:
        textColor = colors.primary;
        backgroundColor = colors.primary.withValues(alpha: 0.15);
        icon = Icons.check_circle_outline;
        label = 'Ready';
        break;
      case TopBarStatus.syncing:
        textColor = colors.tertiary;
        backgroundColor = colors.tertiary.withValues(alpha: 0.15);
        icon = Icons.sync;
        label = 'Syncing';
        break;
      case TopBarStatus.error:
        textColor = colors.error;
        backgroundColor = colors.error.withValues(alpha: 0.15);
        icon = Icons.error_outline;
        label = 'Error';
        break;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
