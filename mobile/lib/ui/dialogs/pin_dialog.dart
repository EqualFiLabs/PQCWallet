import 'package:flutter/material.dart';

Future<String?> showPinSetupDialog(BuildContext context) {
  final pinCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  String? error;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Set wallet PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Enter new PIN',
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final pin = pinCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();
                  if (pin.length < 4) {
                    setState(
                        () => error = 'PIN must be at least 4 digits long.');
                    return;
                  }
                  if (pin != confirm) {
                    setState(() => error = 'PINs do not match.');
                    return;
                  }
                  Navigator.of(ctx).pop(pin);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> showPinEntryDialog(
  BuildContext context, {
  String title = 'Enter wallet PIN',
  String? helperText,
  String? errorText,
}) {
  final ctrl = TextEditingController();
  String? error = errorText;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    helperText: helperText,
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final pin = ctrl.text.trim();
                  if (pin.isEmpty) {
                    setState(() => error = 'PIN required.');
                    return;
                  }
                  Navigator.of(ctx).pop(pin);
                },
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      );
    },
  );
}
