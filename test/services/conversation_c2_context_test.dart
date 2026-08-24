import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/conversation_context_envelope.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/life_context/life_context_graph.dart';
import 'package:moms_ai/models/life_context/life_context_projection.dart';
import 'package:moms_ai/services/conversation_context_assembler.dart';

void main() {
  test('contract exposes closed bounded transport budgets', () {
    expect(
        ConversationTransportContract.purposeId, 'conversation.transport.v1');
    expect(ConversationTransportContract.maximumUserMessageCharacters, 4000);
    expect(ConversationTransportContract.maximumHistoryMessages, 8);
    expect(ConversationTransportContract.maximumRequestUtf8Bytes, 48000);
    expect(ConversationTransportContract.redactionVersion, 1);
  });

  test('complete projection becomes deterministic minimal envelope', () {
    final envelope = ConversationContextAssembler.assemble(_projection());
    expect(envelope.state, ConversationContextState.complete);
    expect(envelope.sections.single.type, 'human');
    expect(envelope.toJson(), envelope.toJson());
    expect(envelope.toJson().toString(), isNot(contains('account-test')));
    expect(envelope.toJson().toString(), isNot(contains('snapshot-1')));
  });

  test('partial and stale states remain explicit', () {
    final partial = ConversationContextAssembler.assemble(
      _projection(state: LifeContextProjectionState.partial),
    );
    expect(partial.state, ConversationContextState.partial);

    final stale = ConversationContextAssembler.assemble(
      _projection(freshness: LifeContextFreshness.stale),
    );
    expect(stale.state, ConversationContextState.stale);
  });

  test('unavailable envelope is not represented as complete empty context', () {
    final envelope = ConversationContextEnvelope.unavailable(
      state: ConversationContextState.unavailable,
      generatedAt: DateTime.utc(2026, 7, 23),
      warningCode: 'context_unavailable',
    );
    expect(envelope.state, ConversationContextState.unavailable);
    expect(envelope.sections, isEmpty);
    expect(envelope.warningCodes, ['context_unavailable']);
  });

  test('request validates current message without silent truncation', () {
    final envelope = ConversationContextAssembler.assemble(_projection());
    final request = ChatBackendRequest(
      message: 'Bonjour\nZélia',
      context: envelope,
    );
    expect(request.toJson()['message'], 'Bonjour\nZélia');
    expect(request.toJson()['schemaVersion'], 2);
    expect(request.toJson()['profile'], isEmpty);
  });

  test('too long and multibyte oversized messages are refused', () {
    final envelope = ConversationContextAssembler.assemble(_projection());
    expect(
      () => ChatBackendRequest(
        message: 'a' *
            (ConversationTransportContract.maximumUserMessageCharacters + 1),
        context: envelope,
      ).toJson(),
      throwsFormatException,
    );
    expect(
      () => ChatBackendRequest(
        message: '🧡' * 3500,
        context: envelope,
      ).toJson(),
      throwsFormatException,
    );
  });

  test('history is ordered bounded and has no technical pending state', () {
    final request = ChatBackendRequest(
      message: 'suite',
      context: ConversationContextAssembler.assemble(_projection()),
      history: [
        ConversationHistoryMessage(role: 'user', text: 'avant'),
        ConversationHistoryMessage(role: 'assistant', text: 'réponse'),
      ],
    );
    expect(
      request.toJson()['conversationHistory'],
      [
        {'role': 'user', 'text': 'avant'},
        {'role': 'assistant', 'text': 'réponse'},
      ],
    );
  });

  test('schema future and missing canonical envelope are refused before send',
      () {
    expect(
      () => const ChatBackendRequest(
        schemaVersion: 3,
        message: 'bonjour',
      ).toJson(),
      throwsFormatException,
    );
    expect(
      () => const ChatBackendRequest(message: 'bonjour').toJson(),
      throwsFormatException,
    );
  });

  test('final UTF-8 payload stays below transport margin', () {
    final request = ChatBackendRequest(
      message: 'bonjour',
      context: ConversationContextAssembler.assemble(_projection()),
    );
    expect(
      utf8.encode(jsonEncode(request.toJson())).length,
      lessThanOrEqualTo(ConversationTransportContract.maximumRequestUtf8Bytes),
    );
  });

  test('one oversized fact cannot erase the shopping section', () {
    final envelope = ConversationContextAssembler.assemble(
      _projectionWithOversizedHumanFactAndShopping(),
    );

    final human = envelope.sections.singleWhere(
      (section) => section.type == 'human',
    );
    final shopping = envelope.sections.singleWhere(
      (section) => section.type == 'shopping',
    );
    expect(
      human.items.single.facts[LifeContextProjectionFactKeys.displayName]!
          .length,
      ConversationTransportContract.maximumFactCharacters,
    );
    expect(shopping.availability, 'available');
    expect(
      shopping.items.single.facts[LifeContextProjectionFactKeys.title],
      'bas',
    );
    expect(
      envelope.warningCodes,
      contains('conversation_context_item_sanitized'),
    );
  });

  test('one malformed transport item cannot erase valid sibling sections', () {
    final projection = _projectionWithOversizedHumanFactAndShopping();
    final human = projection.sections.first;
    final envelope = ConversationContextAssembler.assemble(
      LifeContextProjection(
        projectionId: projection.projectionId,
        sourceSnapshotId: projection.sourceSnapshotId,
        accountScopeId: projection.accountScopeId,
        purpose: projection.purpose,
        generatedAt: projection.generatedAt,
        state: projection.state,
        budgetRequested: projection.budgetRequested,
        budgetUsed: projection.budgetUsed,
        sections: [
          LifeContextProjectionSection(
            type: human.type,
            availability: human.availability,
            freshness: human.freshness,
            items: [
              LifeContextProjectionItem(
                id: 'redacted-only',
                domain: LifeContextDomain.human,
                type: 'personProfileFact',
                facts: [
                  LifeContextProjectionFact(
                    key: LifeContextProjectionFactKeys.profileFactKey,
                    value: 'internal-only',
                    sensitivity: LifeContextSensitivityLevel.publicTechnical,
                  ),
                ],
                confirmation: LifeContextConfirmation.confirmed,
                freshness: LifeContextFreshness.current,
                provenance: const LifeContextProjectionProvenance(
                  sourceDomain: LifeContextDomain.human,
                  sourceId: 'redacted-only',
                  sourceSnapshotId: 'snapshot-shopping',
                  sourceKind: LifeContextSourceKind.humanModelLocal,
                ),
              ),
            ],
            budgetLimit: human.budgetLimit,
            budgetUsed: 2,
            omittedCount: 0,
            truncated: false,
          ),
          projection.sections.last,
        ],
        omittedCount: 0,
        warningCodes: const [],
      ),
    );

    expect(
      envelope.sections.singleWhere((section) => section.type == 'human').items,
      isEmpty,
    );
    expect(
      envelope.sections
          .singleWhere((section) => section.type == 'shopping')
          .items
          .single
          .facts[LifeContextProjectionFactKeys.title],
      'bas',
    );
    expect(envelope.state, ConversationContextState.complete);
    expect(
      envelope.warningCodes,
      contains('conversation_context_item_omitted'),
    );
  });
}

LifeContextProjection _projectionWithOversizedHumanFactAndShopping() =>
    LifeContextProjection(
      projectionId: 'projection-shopping',
      sourceSnapshotId: 'snapshot-shopping',
      accountScopeId: 'account-test',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: DateTime.utc(2026, 8, 24),
      state: LifeContextProjectionState.complete,
      budgetRequested: 330,
      budgetUsed: 9,
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.human,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: [
            LifeContextProjectionItem(
              id: 'person-long',
              domain: LifeContextDomain.human,
              type: 'person',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.displayName,
                  value: 'a' * 120,
                  sensitivity: LifeContextSensitivityLevel.ordinaryPersonal,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: LifeContextFreshness.current,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.human,
                sourceId: 'person-long',
                sourceSnapshotId: 'snapshot-shopping',
                sourceKind: LifeContextSourceKind.humanModelLocal,
              ),
            ),
          ],
          budgetLimit: 55,
          budgetUsed: 2,
          omittedCount: 0,
          truncated: false,
        ),
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.shopping,
          availability: LifeContextAvailability.available,
          freshness: LifeContextFreshness.current,
          items: [
            LifeContextProjectionItem(
              id: 'shopping-bas',
              domain: LifeContextDomain.shopping,
              type: 'shoppingItem',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.status,
                  value: 'active',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.title,
                  value: 'bas',
                  sensitivity: LifeContextSensitivityLevel.ordinaryPersonal,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: LifeContextFreshness.current,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.shopping,
                sourceId: 'shopping-bas',
                sourceSnapshotId: 'snapshot-shopping',
                sourceKind: LifeContextSourceKind.shoppingService,
              ),
            ),
          ],
          budgetLimit: 25,
          budgetUsed: 3,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes: const [],
    );

LifeContextProjection _projection({
  LifeContextProjectionState state = LifeContextProjectionState.complete,
  LifeContextFreshness freshness = LifeContextFreshness.current,
}) =>
    LifeContextProjection(
      projectionId: 'projection-1',
      sourceSnapshotId: 'snapshot-1',
      accountScopeId: 'account-test',
      purpose: LifeContextConsumerPurpose.conversation,
      generatedAt: DateTime.utc(2026, 7, 23),
      state: state,
      budgetRequested: 245,
      budgetUsed: 3,
      sections: [
        LifeContextProjectionSection(
          type: LifeContextProjectionSectionType.human,
          availability: freshness == LifeContextFreshness.stale
              ? LifeContextAvailability.availableStale
              : LifeContextAvailability.available,
          freshness: freshness,
          items: [
            LifeContextProjectionItem(
              id: 'person-1',
              domain: LifeContextDomain.human,
              type: 'person',
              facts: [
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.status,
                  value: 'active',
                  sensitivity: LifeContextSensitivityLevel.publicTechnical,
                ),
                LifeContextProjectionFact(
                  key: LifeContextProjectionFactKeys.displayName,
                  value: 'Personne',
                  sensitivity: LifeContextSensitivityLevel.ordinaryPersonal,
                ),
              ],
              confirmation: LifeContextConfirmation.confirmed,
              freshness: freshness,
              provenance: const LifeContextProjectionProvenance(
                sourceDomain: LifeContextDomain.human,
                sourceId: 'person-1',
                sourceSnapshotId: 'snapshot-1',
                sourceKind: LifeContextSourceKind.humanModelLocal,
              ),
            ),
          ],
          budgetLimit: 55,
          budgetUsed: 3,
          omittedCount: 0,
          truncated: false,
        ),
      ],
      omittedCount: 0,
      warningCodes:
          state == LifeContextProjectionState.partial ? ['source_partial'] : [],
    );
