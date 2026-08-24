import '../models/conversation_context_envelope.dart';
import '../models/life_context/life_context_projection.dart';

abstract final class ConversationContextAssembler {
  // Keep this closed list aligned with the callable transport contract. The
  // life-context projection is richer than the public conversation payload:
  // unsupported facts must never invalidate the whole conversation context.
  static const Set<String> _transportFactKeys = {
    LifeContextProjectionFactKeys.displayName,
    LifeContextProjectionFactKeys.birthDate,
    LifeContextProjectionFactKeys.personRole,
    LifeContextProjectionFactKeys.familyStatus,
    LifeContextProjectionFactKeys.workStatus,
    LifeContextProjectionFactKeys.nodeId,
    LifeContextProjectionFactKeys.relationRole,
    LifeContextProjectionFactKeys.status,
    LifeContextProjectionFactKeys.kind,
    LifeContextProjectionFactKeys.start,
    LifeContextProjectionFactKeys.end,
    LifeContextProjectionFactKeys.dueDate,
    LifeContextProjectionFactKeys.durationMinutes,
    LifeContextProjectionFactKeys.travelGoMinutes,
    LifeContextProjectionFactKeys.travelBackMinutes,
    LifeContextProjectionFactKeys.marginMinutes,
    LifeContextProjectionFactKeys.recurringType,
    LifeContextProjectionFactKeys.syncStatus,
    LifeContextProjectionFactKeys.revision,
    LifeContextProjectionFactKeys.days,
    LifeContextProjectionFactKeys.startTime,
    LifeContextProjectionFactKeys.endTime,
    LifeContextProjectionFactKeys.travelMinutes,
    LifeContextProjectionFactKeys.routineKind,
    LifeContextProjectionFactKeys.subjectNodeId,
    LifeContextProjectionFactKeys.title,
    LifeContextProjectionFactKeys.category,
    LifeContextProjectionFactKeys.sourceNodeId,
    LifeContextProjectionFactKeys.targetNodeId,
    LifeContextProjectionFactKeys.actionRequired,
    LifeContextProjectionFactKeys.importance,
    LifeContextProjectionFactKeys.urgency,
    LifeContextProjectionFactKeys.flexibility,
    LifeContextProjectionFactKeys.createdAt,
    LifeContextProjectionFactKeys.quantity,
    LifeContextProjectionFactKeys.relationshipStatus,
    LifeContextProjectionFactKeys.marriageDate,
    LifeContextProjectionFactKeys.engagementDate,
  };

  static ConversationContextEnvelope assemble(
    LifeContextProjection projection,
  ) {
    if (projection.purpose != LifeContextConsumerPurpose.conversation) {
      throw const FormatException('conversation_projection_required');
    }
    var omittedItemCount = 0;
    var sanitizedItemCount = 0;
    final sections = projection.sections.map((section) {
      var sectionWasSanitized = false;
      var sectionOmittedItems = 0;
      final items = <ConversationContextItem>[];
      for (final item in section.items) {
        final selectedFacts = item.facts
            .where(
              (fact) =>
                  _allowedFact(fact) && _transportFactKeys.contains(fact.key),
            )
            .map(
              (fact) => MapEntry(fact.key, _boundedFactValue(fact.value)),
            )
            .where((entry) => entry.value.isNotEmpty)
            .toList()
          ..sort(_compareFactsForTransport);
        final factsWereFiltered = selectedFacts.length != item.facts.length;
        final factsWereBounded = selectedFacts.any(
          (entry) =>
              item.facts.firstWhere((fact) => fact.key == entry.key).value !=
              entry.value,
        );
        final boundedFacts = selectedFacts
            .take(ConversationTransportContract.maximumFactsPerItem)
            .toList(growable: false);
        final factsWereLimited = boundedFacts.length != selectedFacts.length;
        if (boundedFacts.isEmpty) {
          omittedItemCount++;
          sectionOmittedItems++;
          sectionWasSanitized = true;
          continue;
        }
        try {
          items.add(
            ConversationContextItem(
              type: item.type,
              confirmation: item.confirmation.name,
              freshness: item.freshness.name,
              facts: Map<String, String>.fromEntries(boundedFacts),
            ),
          );
          if (factsWereFiltered || factsWereBounded || factsWereLimited) {
            sanitizedItemCount++;
            sectionWasSanitized = true;
          }
        } on FormatException {
          // One malformed source item must not erase every otherwise valid
          // section (shopping, agenda, tasks, profile, and memory).
          omittedItemCount++;
          sectionOmittedItems++;
          sectionWasSanitized = true;
        }
      }
      return ConversationContextSection(
        type: section.type.name,
        availability: section.availability.name,
        freshness: section.freshness.name,
        items: items,
        budgetLimit: section.budgetLimit,
        budgetUsed: section.budgetUsed,
        omittedCount: section.omittedCount + sectionOmittedItems,
        truncated: section.truncated || sectionWasSanitized,
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
      omittedCount: projection.omittedCount + omittedItemCount,
      truncatedSections: sections
          .where((section) => section.truncated)
          .map((section) => section.type)
          .toList(),
      warningCodes: {
        ...projection.warningCodes,
        if (sanitizedItemCount > 0) 'conversation_context_item_sanitized',
        if (omittedItemCount > 0) 'conversation_context_item_omitted',
      }.toList(growable: false),
    );
  }

  static int _compareFactsForTransport(
    MapEntry<String, String> first,
    MapEntry<String, String> second,
  ) {
    final priority = _factPriority(first.key).compareTo(
      _factPriority(second.key),
    );
    return priority != 0 ? priority : first.key.compareTo(second.key);
  }

  static int _factPriority(String key) => switch (key) {
        LifeContextProjectionFactKeys.title ||
        LifeContextProjectionFactKeys.displayName =>
          0,
        LifeContextProjectionFactKeys.status ||
        LifeContextProjectionFactKeys.kind ||
        LifeContextProjectionFactKeys.personRole ||
        LifeContextProjectionFactKeys.relationRole ||
        LifeContextProjectionFactKeys.routineKind =>
          1,
        LifeContextProjectionFactKeys.start ||
        LifeContextProjectionFactKeys.end ||
        LifeContextProjectionFactKeys.dueDate ||
        LifeContextProjectionFactKeys.startTime ||
        LifeContextProjectionFactKeys.endTime =>
          2,
        LifeContextProjectionFactKeys.durationMinutes ||
        LifeContextProjectionFactKeys.urgency ||
        LifeContextProjectionFactKeys.quantity ||
        LifeContextProjectionFactKeys.category =>
          3,
        _ => 4,
      };

  static String _boundedFactValue(String value) {
    final normalized = value.trim();
    final maximum = ConversationTransportContract.maximumFactCharacters;
    if (normalized.length <= maximum) return normalized;
    var end = maximum;
    final finalCodeUnit = normalized.codeUnitAt(end - 1);
    if (finalCodeUnit >= 0xD800 && finalCodeUnit <= 0xDBFF) end--;
    return normalized.substring(0, end).trimRight();
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
