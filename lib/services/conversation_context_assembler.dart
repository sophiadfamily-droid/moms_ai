import '../models/conversation_context_envelope.dart';
import '../models/life_context/life_context_projection.dart';

abstract final class ConversationContextAssembler {
  static ConversationContextEnvelope assemble(
    LifeContextProjection projection,
  ) {
    if (projection.purpose != LifeContextConsumerPurpose.conversation) {
      throw const FormatException('conversation_projection_required');
    }
    var redactedCount = 0;
    final sections = projection.sections.map((section) {
      final items = section.items
          .map((item) {
            final facts = <String, String>{
              for (final fact in item.facts)
                if (_allowedFact(fact)) fact.key: fact.value,
            };
            if (facts.isEmpty) {
              redactedCount++;
              return null;
            }
            return ConversationContextItem(
              type: item.type,
              confirmation: item.confirmation.name,
              freshness: item.freshness.name,
              facts: facts,
            );
          })
          .whereType<ConversationContextItem>()
          .toList(growable: false);
      return ConversationContextSection(
        type: section.type.name,
        availability: section.availability.name,
        freshness: section.freshness.name,
        items: items,
        budgetLimit: section.budgetLimit,
        budgetUsed: section.budgetUsed,
        omittedCount:
            section.omittedCount + section.items.length - items.length,
        truncated: section.truncated || items.length != section.items.length,
      );
    }).toList(growable: false);
    final stale = sections.any(
      (section) =>
          section.freshness == 'stale' ||
          section.availability == 'availableStale',
    );
    return ConversationContextEnvelope(
      projectionVersion: projection.schemaVersion,
      purpose: ConversationTransportContract.purposeId,
      generatedAt: projection.generatedAt,
      state: stale
          ? ConversationContextState.stale
          : projection.state == LifeContextProjectionState.partial
              ? ConversationContextState.partial
              : ConversationContextState.complete,
      sections: sections,
      budgetRequested: projection.budgetRequested,
      budgetUsed: projection.budgetUsed,
      omittedCount: projection.omittedCount + redactedCount,
      truncatedSections: sections
          .where((section) => section.truncated)
          .map((section) => section.type)
          .toList(),
      warningCodes: projection.warningCodes,
    );
  }

  static bool _allowedFact(LifeContextProjectionFact fact) {
    if (!const {
      LifeContextSensitivityLevel.publicTechnical,
      LifeContextSensitivityLevel.ordinaryPersonal,
      LifeContextSensitivityLevel.privatePersonal,
    }.contains(fact.sensitivity)) {
      return false;
    }
    return !const {
      'allergies',
      'medicalNotes',
      'bloodType',
      'doctorName',
      'emergencyContactName',
      'emergencyContactPhone',
      'address',
      'phone',
      'token',
      'secret',
    }.contains(fact.key);
  }
}
