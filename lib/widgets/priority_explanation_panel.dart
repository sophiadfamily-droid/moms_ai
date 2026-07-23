import 'package:flutter/material.dart';

import '../models/priority/priority_explanation_models.dart';

class PriorityExplanationPanel extends StatelessWidget {
  const PriorityExplanationPanel({
    super.key,
    required this.explanation,
  });

  final PriorityExplanation explanation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Explication de la priorité',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pourquoi cette priorité ?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(explanation.shortText),
              if (explanation.detailLevel ==
                  PriorityExplanationDetailLevel.detailed) ...[
                const SizedBox(height: 12),
                for (final paragraph in explanation.paragraphs) ...[
                  Text(paragraph),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
