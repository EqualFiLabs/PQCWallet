import 'package:flutter/material.dart';

import '../state/fees.dart';

Future<FeeState?> showFeeSheet(BuildContext context, FeeState fees) {
  return showModalBottomSheet<FeeState>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FeeSheet(initial: fees));
}

class _FeeSheet extends StatefulWidget {
  final FeeState initial;
  const _FeeSheet({required this.initial});

  @override
  State<_FeeSheet> createState() => _FeeSheetState();
}

class _FeeSheetState extends State<_FeeSheet> {
  late FeeState _fees;
  late TextEditingController _maxFeeCtl;
  late TextEditingController _priorityCtl;

  @override
  void initState() {
    super.initState();
    _fees = widget.initial;
    _maxFeeCtl = TextEditingController(text: weiToGwei(_fees.maxFeePerGas));
    _priorityCtl =
        TextEditingController(text: weiToGwei(_fees.maxPriorityFeePerGas));
    _maxFeeCtl.addListener(_onChanged);
    _priorityCtl.addListener(_onChanged);
  }

  void _onChanged() {
    setState(() {
      _fees = _fees.copyWith(
        maxFeePerGas: gweiToWei(_maxFeeCtl.text),
        maxPriorityFeePerGas: gweiToWei(_priorityCtl.text),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Fee Preview', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _row('Base fee (gwei)', weiToGwei(_fees.baseFee)),
          _row('Priority suggestion (gwei)',
              weiToGwei(_fees.prioritySuggestion)),
          _row('Gas total', _fees.totalGas.toString()),
          const SizedBox(height: 8),
          TextField(
            controller: _priorityCtl,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Max priority fee (gwei)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _maxFeeCtl,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Max fee per gas (gwei)'),
          ),
          const SizedBox(height: 12),
          _row('Network fee (ETH)', weiToEth(_fees.networkFeeWei)),
          _row('Bundler fee (ETH)', weiToEth(_fees.bundlerFeeWei)),
          _row('Total fee (ETH)', weiToEth(_fees.totalFeeWei)),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel')),
              const Spacer(),
              TextButton(
                  onPressed: () {
                    final s = widget.initial;
                    _maxFeeCtl.text = weiToGwei(s.maxFeePerGas);
                    _priorityCtl.text = weiToGwei(s.maxPriorityFeePerGas);
                  },
                  child: const Text('Use suggestions')),
              const SizedBox(width: 8),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, _fees),
                  child: const Text('Confirm')),
            ],
          )
        ],
      ),
    );
  }

  Widget _row(String label, String value) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label),
        Text(value),
      ]);
}
