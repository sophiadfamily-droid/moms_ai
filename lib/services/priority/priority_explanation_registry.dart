import '../../models/priority/priority_explanation_models.dart';
import '../../models/priority/priority_models.dart';

final class PriorityExplanationReasonDefinition {
  const PriorityExplanationReasonDefinition({
    required this.code,
    required this.polarity,
    required this.shortText,
    required this.detailedText,
  });

  final PriorityExplanationReasonCode code;
  final PriorityExplanationPolarity polarity;
  final String shortText;
  final String detailedText;
}

abstract final class PriorityExplanationRegistry {
  static const int version = 1;

  static const Map<PriorityExplanationReasonCode,
      PriorityExplanationReasonDefinition> definitions = {
    PriorityExplanationReasonCode.overdue: PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.overdue,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son échéance est dépassée',
      detailedText:
          'L’échéance renseignée est dépassée, ce qui augmente la pression temporelle.',
    ),
    PriorityExplanationReasonCode.dueVerySoon:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.dueVerySoon,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son échéance est très proche',
      detailedText:
          'L’échéance se situe dans moins de deux heures, selon les données structurées.',
    ),
    PriorityExplanationReasonCode.dueToday: PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.dueToday,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son échéance est prévue aujourd’hui',
      detailedText:
          'L’échéance structurée se situe aujourd’hui et contribue au score direct.',
    ),
    PriorityExplanationReasonCode.dueTomorrow:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.dueTomorrow,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son échéance est prévue demain',
      detailedText:
          'L’échéance structurée se situe demain et contribue au score direct.',
    ),
    PriorityExplanationReasonCode.dueSoon: PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.dueSoon,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son échéance approche',
      detailedText:
          'L’échéance se situe dans la fenêtre proche utilisée par le calcul.',
    ),
    PriorityExplanationReasonCode.distantDeadline:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.distantDeadline,
      polarity: PriorityExplanationPolarity.reducing,
      shortText: 'son échéance reste éloignée',
      detailedText:
          'L’échéance est au-delà de la fenêtre proche et exerce peu de pression temporelle.',
    ),
    PriorityExplanationReasonCode.noDeadline:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.noDeadline,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'aucune échéance n’est renseignée',
      detailedText:
          'Aucune échéance n’est renseignée ; le calcul conserve une valeur neutre.',
    ),
    PriorityExplanationReasonCode.explicitUrgency:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.explicitUrgency,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'une urgence a été explicitement indiquée',
      detailedText:
          'Le niveau d’urgence provient d’une valeur structurée explicitement renseignée.',
    ),
    PriorityExplanationReasonCode.explicitImportanceHigh:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.explicitImportanceHigh,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son importance déclarée est élevée',
      detailedText:
          'L’importance structurée a été explicitement renseignée à un niveau élevé.',
    ),
    PriorityExplanationReasonCode.explicitImportanceModerate:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.explicitImportanceModerate,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'son importance déclarée est modérée',
      detailedText:
          'L’importance structurée a été explicitement renseignée à un niveau modéré.',
    ),
    PriorityExplanationReasonCode.explicitImportanceLow:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.explicitImportanceLow,
      polarity: PriorityExplanationPolarity.reducing,
      shortText: 'son importance déclarée est faible',
      detailedText:
          'L’importance structurée a été explicitement renseignée à un niveau faible.',
    ),
    PriorityExplanationReasonCode.importanceUnknown:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.importanceUnknown,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'son importance n’a pas été renseignée',
      detailedText:
          'L’importance n’a pas été renseignée ; le moteur utilise une valeur neutre sans porter de jugement.',
    ),
    PriorityExplanationReasonCode.effortKnown:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.effortKnown,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'sa durée estimée est connue',
      detailedText:
          'La durée estimée est connue. Elle reste neutre seule et sert à évaluer la pression avant échéance.',
    ),
    PriorityExplanationReasonCode.effortUnknown:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.effortUnknown,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'sa durée estimée n’est pas connue',
      detailedText:
          'La durée estimée n’est pas connue ; aucune durée courte ou longue n’est supposée.',
    ),
    PriorityExplanationReasonCode.insufficientTime:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.insufficientTime,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'la durée estimée dépasse le temps restant',
      detailedText:
          'La durée estimée est supérieure au temps restant avant l’échéance.',
    ),
    PriorityExplanationReasonCode.fixed: PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.fixed,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'son créneau est indiqué comme fixe',
      detailedText:
          'Le créneau est indiqué comme fixe dans les données structurées.',
    ),
    PriorityExplanationReasonCode.lowFlexibility:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.lowFlexibility,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'sa flexibilité est limitée',
      detailedText:
          'Cette action est déclarée peu flexible dans les données structurées.',
    ),
    PriorityExplanationReasonCode.flexible: PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.flexible,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'cette action est déclarée flexible',
      detailedText:
          'Cette action est déclarée flexible, ce qui limite la contribution de rigidité.',
    ),
    PriorityExplanationReasonCode.veryFlexible:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.veryFlexible,
      polarity: PriorityExplanationPolarity.reducing,
      shortText: 'cette action est déclarée très flexible',
      detailedText:
          'Cette action est déclarée très flexible et reçoit une faible contribution de rigidité.',
    ),
    PriorityExplanationReasonCode.flexibilityUnknown:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.flexibilityUnknown,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'sa flexibilité n’est pas précisée',
      detailedText:
          'La flexibilité n’est pas précisée ; le calcul conserve une valeur neutre.',
    ),
    PriorityExplanationReasonCode.directImpact:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.directImpact,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'un impact direct confirmé est pris en compte',
      detailedText:
          'Un impact direct structuré et confirmé contribue au score direct sans exposer l’élément lié.',
    ),
    PriorityExplanationReasonCode.noDirectImpact:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.noDirectImpact,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'aucun impact direct confirmé n’est pris en compte',
      detailedText:
          'Aucun impact direct structuré et confirmé n’a été utilisé dans le score direct.',
    ),
    PriorityExplanationReasonCode.propagatedDependency:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.propagatedDependency,
      polarity: PriorityExplanationPolarity.positive,
      shortText: 'une dépendance explicite renforce aussi sa priorité',
      detailedText:
          'Un autre élément dépend explicitement de ce prérequis ; cette influence reste bornée et décroît avec la profondeur.',
    ),
    PriorityExplanationReasonCode.noPropagation:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.noPropagation,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'aucune dépendance n’a modifié son score',
      detailedText:
          'Aucune contribution issue d’une dépendance explicite n’a été ajoutée au score direct.',
    ),
    PriorityExplanationReasonCode.staleData:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.staleData,
      polarity: PriorityExplanationPolarity.warning,
      shortText: 'certaines données peuvent être anciennes',
      detailedText:
          'La source disponible est périmée ; le résultat reste utilisable avec cette réserve.',
    ),
    PriorityExplanationReasonCode.missingData:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.missingData,
      polarity: PriorityExplanationPolarity.reducing,
      shortText: 'certaines informations manquent au calcul',
      detailedText:
          'Des informations structurées manquent et réduisent la confiance dans le résultat.',
    ),
    PriorityExplanationReasonCode.partialCalculation:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.partialCalculation,
      polarity: PriorityExplanationPolarity.warning,
      shortText: 'le calcul est partiel',
      detailedText:
          'Le score a pu être calculé, mais certaines dimensions restent incomplètes.',
    ),
    PriorityExplanationReasonCode.cycleDetected:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.cycleDetected,
      polarity: PriorityExplanationPolarity.warning,
      shortText: 'une boucle de dépendances a été limitée',
      detailedText:
          'Une boucle de dépendances a été détectée. Son influence a été limitée pour éviter les doubles comptes.',
    ),
    PriorityExplanationReasonCode.truncatedPropagation:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.truncatedPropagation,
      polarity: PriorityExplanationPolarity.warning,
      shortText: 'certaines dépendances supplémentaires ne sont pas détaillées',
      detailedText:
          'Certaines dépendances supplémentaires n’ont pas été détaillées afin de garder le calcul borné.',
    ),
    PriorityExplanationReasonCode.uncertainDependency:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.uncertainDependency,
      polarity: PriorityExplanationPolarity.warning,
      shortText: 'une dépendance reste incertaine',
      detailedText:
          'Une dépendance issue d’une règle enregistrée reste incertaine et son influence a été réduite.',
    ),
    PriorityExplanationReasonCode.unsupportedCandidate:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.unsupportedCandidate,
      polarity: PriorityExplanationPolarity.warning,
      shortText: 'ce type d’élément ne peut pas être expliqué',
      detailedText:
          'Le calcul disponible ne permet pas de produire une explication complète pour ce type d’élément.',
    ),
    PriorityExplanationReasonCode.higherAdjustedScore:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.higherAdjustedScore,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'son score ajusté est supérieur',
      detailedText:
          'Le premier élément possède un score ajusté supérieur après les influences explicites.',
    ),
    PriorityExplanationReasonCode.higherDirectScore:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.higherDirectScore,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'son score direct est supérieur',
      detailedText:
          'Le premier élément possède un score direct supérieur avant toute propagation.',
    ),
    PriorityExplanationReasonCode.closerDeadline:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.closerDeadline,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'son échéance est plus proche',
      detailedText:
          'Les scores étant équivalents, l’échéance structurée la plus proche départage les éléments.',
    ),
    PriorityExplanationReasonCode.moreRigid:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.moreRigid,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'sa contrainte temporelle est plus rigide',
      detailedText:
          'Les scores et échéances étant équivalents, la rigidité structurée départage les éléments.',
    ),
    PriorityExplanationReasonCode.strongerConfirmation:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.strongerConfirmation,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'ses données sont mieux confirmées',
      detailedText:
          'Les facteurs précédents étant équivalents, le niveau de confirmation départage les éléments.',
    ),
    PriorityExplanationReasonCode.fresherData:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.fresherData,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'ses données sont plus fraîches',
      detailedText:
          'Les facteurs précédents étant équivalents, la fraîcheur des données départage les éléments.',
    ),
    PriorityExplanationReasonCode.stableTieBreak:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.stableTieBreak,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'un ordre stable a été conservé',
      detailedText:
          'Les critères utiles sont équivalents ; un ordre technique stable est conservé sans juger les éléments.',
    ),
    PriorityExplanationReasonCode.equivalentRanking:
        PriorityExplanationReasonDefinition(
      code: PriorityExplanationReasonCode.equivalentRanking,
      polarity: PriorityExplanationPolarity.neutral,
      shortText: 'les deux résultats sont équivalents',
      detailedText:
          'Les scores et les critères de départage disponibles sont équivalents.',
    ),
  };

  static PriorityExplanationReason create(
    PriorityExplanationReasonCode code, {
    required double contribution,
    PriorityDimension? dimension,
    int? depth,
  }) {
    final definition = definitions[code];
    if (definition == null || definition.code != code) {
      throw const PriorityException('unknown_priority_explanation_reason');
    }
    return PriorityExplanationReason(
      code: code,
      polarity: definition.polarity,
      shortText: definition.shortText,
      detailedText: definition.detailedText,
      contribution: contribution,
      dimension: dimension,
      depth: depth,
    );
  }

  static void validate() {
    if (definitions.length != PriorityExplanationReasonCode.values.length ||
        definitions.entries.any(
          (entry) =>
              entry.key != entry.value.code ||
              entry.value.shortText.trim().isEmpty ||
              entry.value.detailedText.trim().isEmpty,
        )) {
      throw const PriorityException('invalid_priority_explanation_registry');
    }
  }
}
