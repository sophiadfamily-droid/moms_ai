import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/priority/priority_explanation_models.dart';
import 'package:moms_ai/models/priority/priority_models.dart';
import 'package:moms_ai/models/priority/priority_propagation_models.dart';
import 'package:moms_ai/services/priority/priority_explanation_registry.dart';
import 'package:moms_ai/widgets/priority_explanation_panel.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(820, 1180),
  ]) {
    testWidgets('panel remains responsive at $size with text scale 1.6',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
                size: size, textScaler: const TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: PriorityExplanationPanel(explanation: _explanation()),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Pourquoi cette priorité ?'), findsOneWidget);
      expect(find.textContaining('échéance'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

PriorityExplanation _explanation() => PriorityExplanation(
      candidateId: 'candidate',
      formulaVersion: 1,
      propagationVersion: 1,
      detailLevel: PriorityExplanationDetailLevel.detailed,
      calculationStatus: PriorityCalculationStatus.partiallyScored,
      confidence: PriorityConfidence.partial,
      shortText:
          'Cette priorité s’explique surtout parce que son échéance est très proche.',
      paragraphs: const [
        'Score direct : 70 sur 100.',
        'Informations manquantes : la flexibilité n’est pas précisée.',
      ],
      primaryReasons: [
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.dueVerySoon,
          contribution: 20,
        ),
      ],
      secondaryReasons: const [],
      reducingFactors: const [],
      missingData: const [PriorityMissingData.flexibility],
      propagationReasons: [
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.noPropagation,
          contribution: 0,
        ),
      ],
      cycleState: PriorityPropagationCycleState.none,
      truncationState: PriorityPropagationTruncationState.complete,
      warnings: [
        PriorityExplanationRegistry.create(
          PriorityExplanationReasonCode.partialCalculation,
          contribution: 0,
        ),
      ],
      sourceSnapshotId: 'snapshot',
      evaluatedAt: DateTime.utc(2026, 7, 23),
    );
