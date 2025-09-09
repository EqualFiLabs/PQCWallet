import 'package:flutter/material.dart';
import '../services/activity_store.dart';
import '../models/activity.dart';

class ActivityFeed extends StatelessWidget {
  final ActivityStore store;
  const ActivityFeed({super.key, required this.store});

  Color _statusColor(ActivityStatus s) {
    switch (s) {
      case ActivityStatus.pending:
        return Colors.orange;
      case ActivityStatus.sent:
        return Colors.blueGrey;
      case ActivityStatus.confirmed:
        return Colors.green;
      case ActivityStatus.failed:
        return Colors.red;
      case ActivityStatus.dropped:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityItem>>(
      stream: store.stream,
      initialData: store.items,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return const Center(child: Text('No activity yet'));
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final it = items[i];
            final shortTo = it.to.length > 10
                ? '${it.to.substring(0, 6)}…${it.to.substring(it.to.length - 4)}'
                : it.to;
            final shortHash = it.userOpHash.length > 10
                ? '${it.userOpHash.substring(0, 8)}…'
                : it.userOpHash;
            final when =
                DateTime.fromMillisecondsSinceEpoch(it.ts * 1000).toLocal();
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _statusColor(it.status),
                child:
                    Text(it.opKind == 'erc20' ? (it.tokenSymbol ?? 'T') : 'Ξ'),
              ),
              title: Text('${it.display} → $shortTo'),
              subtitle: Text('$shortHash • $when'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(it.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(it.status.name),
              ),
            );
          },
        );
      },
    );
  }
}
