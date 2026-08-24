import 'dart:collection';
import 'dart:convert';

import 'life_context/life_context_domains.dart';
import 'life_context/life_context_graph.dart';
import 'life_context/life_context_projection.dart';

enum ConversationContextState {
  complete,
  partial,
  stale,
  unavailable,
  timeout,
  unauthenticated,
  accountMismatch,
  invalidProjection,
  cancelled,
  unknownFailure,
}

final class ConversationTransportContract {
  static const int currentSchemaVersion = 1;
  static const int redactionVersion = 1;
  static const String purposeId = 'conversation.transport.v1';
  static const int maximumUserMessageCharacters = 4000;
  static const int maximumMessageUtf8Bytes = 12000;
  static const int maximumHistoryMessages = 8;
  static const int maximumHistoryMessageCharacters = 1000;
  static const int maximumHistoryUtf8Bytes = 8000;
  static const int maximumContextUtf8Bytes = 24000;
  static const int maximumRequestUtf8Bytes = 48000;
  // Conversation carries the seven existing read sections plus Shopping.
  static const int maximumSections = 8;
  static const int maximumItems = 40;
  static const int maximumFactsPerItem = 12;
  static const int maximumFactCharacters = 80;
  static const Duration contextTimeout = Duration(seconds: 7);

  const ConversationTransportContract();
}

final class ConversationContextItem {
  ConversationContextItem({
    required this.type,
    required this.confirmation,
    required this.freshness,
    required Map<String, String> facts,
  }) : facts = UnmodifiableMapView(
          Map<String, String>.fromEntries(
            facts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
          ),
        ) {
    if (type.trim().isEmpty ||
        !LifeContextConfirmation.values
            .map((value) => value.name)
            .contains(confirmation) ||
        !LifeContextFreshness.values
            .map((value) => value.name)
            .contains(freshness) ||
        !LifeContextProjectionFactKeys.all.containsAll(this.facts.keys) ||
        this.facts.isEmpty ||
        this.facts.length > ConversationTransportContract.maximumFactsPerItem ||
        this.facts.values.any(
              (value) =>
                  value.isEmpty ||
                  value.length >
                      ConversationTransportContract.maximumFactCharacters,
            )) {
      throw const FormatException('invalid_conversation_context_item');
    }
  }

  final String type;
  final String confirmation;
  final String freshness;
  final Map<String, String> facts;

  Map<String, Object> toJson() => {
        'type': type,
        'confirmation': confirmation,
        'freshness': freshness,
        'facts': facts,
      };
}

final class ConversationContextSection {
  ConversationContextSection({
    required this.type,
    required this.availability,
    required this.freshness,
    required List<ConversationContextItem> items,
    required this.budgetLimit,
    required this.budgetUsed,
    required this.omittedCount,
    required this.truncated,
  }) : items = UnmodifiableListView(items) {
    if (!LifeContextProjectionSectionType.values
            .map((value) => value.name)
            .contains(type) ||
        !LifeContextAvailability.values
            .map((value) => value.name)
            .contains(availability) ||
        !LifeContextFreshness.values
            .map((value) => value.name)
            .contains(freshness) ||
        budgetLimit < 1 ||
        budgetUsed < 0 ||
        budgetUsed > budgetLimit ||
        omittedCount < 0) {
      throw const FormatException('invalid_conversation_context_section');
    }
  }

  final String type;
  final String availability;
  final String freshness;
  final List<ConversationContextItem> items;
  final int budgetLimit;
  final int budgetUsed;
  final int omittedCount;
  final bool truncated;

  Map<String, Object> toJson() => {
        'type': type,
        'availability': availability,
        'freshness': freshness,
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'budgetLimit': budgetLimit,
        'budgetUsed': budgetUsed,
        'omittedCount': omittedCount,
        'truncated': truncated,
      };
}

final class ConversationContextEnvelope {
  static const int currentSchemaVersion = 1;

  ConversationContextEnvelope({
    this.schemaVersion = currentSchemaVersion,
    required this.projectionVersion,
    required this.purpose,
    required this.generatedAt,
    required this.state,
    required List<ConversationContextSection> sections,
    required this.budgetRequested,
    required this.budgetUsed,
    required this.omittedCount,
    required List<String> truncatedSections,
    required List<String> warningCodes,
    this.redactionVersion = ConversationTransportContract.redactionVersion,
  })  : sections = UnmodifiableListView(sections),
        truncatedSections = UnmodifiableListView(
          List<String>.of(truncatedSections)..sort(),
        ),
        warningCodes = UnmodifiableListView(
          List<String>.of(warningCodes)..sort(),
        ) {
    if (schemaVersion != currentSchemaVersion ||
        projectionVersion < 0 ||
        purpose != ConversationTransportContract.purposeId ||
        budgetRequested < 1 ||
        budgetUsed < 0 ||
        budgetUsed > budgetRequested ||
        omittedCount < 0 ||
        redactionVersion != ConversationTransportContract.redactionVersion ||
        sections.length > ConversationTransportContract.maximumSections ||
        sections.fold<int>(
                0, (count, section) => count + section.items.length) >
            ConversationTransportContract.maximumItems) {
      throw const FormatException('invalid_conversation_context_envelope');
    }
    if (utf8.encode(jsonEncode(toJson())).length >
        ConversationTransportContract.maximumContextUtf8Bytes) {
      throw const FormatException('conversation_context_budget_exceeded');
    }
  }

  factory ConversationContextEnvelope.unavailable({
    required ConversationContextState state,
    required DateTime generatedAt,
    required String warningCode,
  }) =>
      ConversationContextEnvelope(
        projectionVersion: 0,
        purpose: ConversationTransportContract.purposeId,
        generatedAt: generatedAt.toUtc(),
        state: state,
        sections: const [],
        budgetRequested: LifeContextConsumerContract.forPurpose(
          LifeContextConsumerPurpose.conversation,
        ).globalBudget,
        budgetUsed: 0,
        omittedCount: 0,
        truncatedSections: const [],
        warningCodes: [warningCode],
      );

  final int schemaVersion;
  final int projectionVersion;
  final String purpose;
  final DateTime generatedAt;
  final ConversationContextState state;
  final List<ConversationContextSection> sections;
  final int budgetRequested;
  final int budgetUsed;
  final int omittedCount;
  final List<String> truncatedSections;
  final List<String> warningCodes;
  final int redactionVersion;

  Map<String, Object> toJson() => {
        'schemaVersion': schemaVersion,
        'projectionVersion': projectionVersion,
        'purpose': purpose,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'state': state.name,
        'sections': sections.map((section) => section.toJson()).toList(),
        'budgetRequested': budgetRequested,
        'budgetUsed': budgetUsed,
        'omittedCount': omittedCount,
        'truncatedSections': truncatedSections,
        'warningCodes': warningCodes,
        'redactionVersion': redactionVersion,
      };
}

final class ConversationHistoryMessage {
  ConversationHistoryMessage({
    required this.role,
    required String text,
  }) : text = text.trim() {
    if (!const {'user', 'assistant'}.contains(role) ||
        this.text.isEmpty ||
        this.text.length >
            ConversationTransportContract.maximumHistoryMessageCharacters) {
      throw const FormatException('invalid_conversation_history_message');
    }
  }

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};
}
