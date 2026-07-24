import 'package:flutter/material.dart';

import '../models/action_confirmation.dart';

final class ActionConfirmationDialog extends StatelessWidget {
  const ActionConfirmationDialog({
    super.key,
    required this.presentation,
  });

  final ActionConfirmationPresentation presentation;

  static Future<ActionConfirmationResponseChoice?> show(
    BuildContext context, {
    required ActionConfirmationPresentation presentation,
  }) =>
      showDialog<ActionConfirmationResponseChoice>(
        context: context,
        builder: (_) => ActionConfirmationDialog(presentation: presentation),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(presentation.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(presentation.summary),
              const SizedBox(height: 12),
              Text(
                presentation.consequence,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            ActionConfirmationResponseChoice.cancel,
          ),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            ActionConfirmationResponseChoice.reject,
          ),
          child: const Text('Refuser'),
        ),
        if (presentation.allowPostpone)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              ActionConfirmationResponseChoice.postpone,
            ),
            child: const Text('Plus tard'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ActionConfirmationResponseChoice.accept,
          ),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}
