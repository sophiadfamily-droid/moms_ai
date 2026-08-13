import '../../models/action_autonomy_policy.dart';
import '../../models/human/human_model.dart';
import '../../models/user_profile.dart';
import '../auth_service.dart';
import '../conversation_answer_classifier.dart';
import '../natural_event_request_service.dart';
import '../routine_conversation_service.dart';
import '../school_schedule_metadata_service.dart';
import 'human_model_edit_service.dart';

enum RecurringResponsibilityConversationResultType {
  notResponsibility,
  clarification,
  confirmation,
  saved,
  cancelled,
  unavailable,
}

final class RecurringResponsibilityConversationResult {
  const RecurringResponsibilityConversationResult(this.type, this.message);

  final RecurringResponsibilityConversationResultType type;
  final String message;
}

typedef HumanModelEditorLoader = Future<HumanModelEditService> Function();

/// Understands explicit recurring responsibilities for any known person and
/// proposes one bounded clarification when a child's structured school
/// schedule reveals a likely missing transition.
///
/// Explicit drop-off and pickup statements are universal: neither age nor a
/// family-role label is required. Automatic clarification is deliberately
/// child-only; an adult's schedule never implies transport. A child's school
/// schedule can trigger the question, but never becomes a responsibility or a
/// planning blocker by itself. A canonical HumanModel mutation happens only
/// after one explicit confirmation. A rejection is retained so the same
/// question is not asked again.
final class RecurringResponsibilityConversationService {
  factory RecurringResponsibilityConversationService.production() =>
      RecurringResponsibilityConversationService(
        currentAccountScopeId: () => AuthService.currentUserId,
        loadEditor: HumanModelEditService.createProduction,
      );

  RecurringResponsibilityConversationService({
    required String? Function() currentAccountScopeId,
    required HumanModelEditorLoader loadEditor,
  })  : _currentAccountScopeId = currentAccountScopeId,
        _loadEditor = loadEditor;

  final String? Function() _currentAccountScopeId;
  final HumanModelEditorLoader _loadEditor;
  final ConversationAnswerClassifier _answers =
      const ConversationAnswerClassifier();

  HumanModelEditService? _editor;
  _RecurringResponsibilityDraft? _pending;
  _SchoolTransitionProposal? _pendingSchoolTransition;

  bool get hasPending => _pending != null || _pendingSchoolTransition != null;

  void invalidate() {
    _pending = null;
    _pendingSchoolTransition = null;
  }

  /// Proposes at most one missing school drop-off responsibility.
  ///
  /// The profile supplies the child's explicit schedule. HumanModel supplies
  /// the canonical people and any answer already given. No write and no
  /// availability block happens before the user answers.
  Future<RecurringResponsibilityConversationResult> proposeSchoolDropoff(
    UserProfile profile,
  ) =>
      _proposeSchoolTransition(
        profile,
        kinds: const [_SchoolTransitionKind.dropoff],
      );

  /// Compatibility entry point used by focused tests and future profile
  /// flows. It never infers that the user collects the child: it only asks
  /// the bounded question and waits for an explicit answer.
  Future<RecurringResponsibilityConversationResult> proposeSchoolPickup(
    UserProfile profile,
  ) =>
      _proposeSchoolTransition(
        profile,
        kinds: const [_SchoolTransitionKind.pickup],
      );

  /// Backward-compatible name for the former entry-only behavior. The shared
  /// implementation now checks both school-entry and school-exit transitions.
  Future<RecurringResponsibilityConversationResult>
      proposeSchoolDropoffForPlanningRequest(
    UserProfile profile,
    String message, {
    DateTime? now,
  }) =>
          proposeSchoolTransitionForPlanningRequest(
            profile,
            message,
            now: now,
          );

  /// Asks about an entry or exit responsibility only when the requested
  /// Event actually touches that transition. Entry and exit decisions are
  /// retained independently because one person may handle only one of them.
  Future<RecurringResponsibilityConversationResult>
      proposeSchoolTransitionForPlanningRequest(
    UserProfile profile,
    String message, {
    DateTime? now,
  }) async {
    final action = NaturalEventRequestService.parseAction(message, now: now);
    final date = DateTime.tryParse(action?['date']?.toString() ?? '');
    final time = _SchoolTransitionRange.canonicalTime(
      action?['time']?.toString() ?? '',
    );
    if (date == null || time == null) return _notResponsibility;
    return _proposeSchoolTransition(
      profile,
      relevantWeekday: date.weekday,
      relevantTime: time,
      kinds: _SchoolTransitionKind.values,
    );
  }

  Future<RecurringResponsibilityConversationResult> _proposeSchoolTransition(
    UserProfile profile, {
    int? relevantWeekday,
    String? relevantTime,
    required List<_SchoolTransitionKind> kinds,
  }) async {
    if (hasPending) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.notResponsibility,
        '',
      );
    }
    final scope = _currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) return _unavailable;
    final editor = await _getEditor();
    final state = await editor.load(scope);
    final model = state?.model;
    if (model == null || model.accountScopeId != scope) return _unavailable;

    for (final child in profile.children) {
      final person = _personForChild(model, child);
      if (person == null || child.schoolTimeRanges.isEmpty) {
        continue;
      }
      final displayName = person.displayName?.trim().isNotEmpty == true
          ? person.displayName!.trim()
          : child.firstName.trim();
      for (final kind in kinds) {
        final ranges = _SchoolTransitionRange.boundaryPerWeekday(
          child.schoolTimeRanges
              .map((range) => _SchoolTransitionRange.fromProfile(range, kind))
              .whereType<_SchoolTransitionRange>(),
          kind,
        );
        if (_hasSchoolTransitionDecision(model, person.id, kind, ranges)) {
          await _synchronizeConfirmedSchoolTransition(
            editor: editor,
            model: model,
            subjectPersonId: person.id,
            subjectDisplayName: displayName,
            ranges: ranges,
            kind: kind,
          );
          continue;
        }
        if (ranges.isEmpty ||
            (relevantWeekday != null &&
                relevantTime != null &&
                !ranges.any(
                  (range) => range.isRelevantTo(
                    weekday: relevantWeekday,
                    time: relevantTime,
                  ),
                ))) {
          continue;
        }
        final proposal = _SchoolTransitionProposal(
          kind: kind,
          subjectPersonId: person.id,
          subjectDisplayName: displayName,
          ranges: ranges,
        );
        _pendingSchoolTransition = proposal;
        return RecurringResponsibilityConversationResult(
          RecurringResponsibilityConversationResultType.confirmation,
          proposal.question,
        );
      }
    }
    return _notResponsibility;
  }

  Future<RecurringResponsibilityConversationResult> process(
    String message,
  ) async {
    final schoolTransition = _pendingSchoolTransition;
    if (schoolTransition != null) {
      return _resolveSchoolTransition(message, schoolTransition);
    }
    final pending = _pending;
    if (pending != null) {
      if (_answers.classify(message) == ConversationAnswer.negative) {
        _pending = null;
        return const RecurringResponsibilityConversationResult(
          RecurringResponsibilityConversationResultType.cancelled,
          'D’accord, je ne l’ajoute pas.',
        );
      }
      if (pending.isComplete) return _resolveConfirmation(message, pending);
      return _completeClarification(message, pending);
    }

    final parsed = _RecurringResponsibilityParser.parse(message);
    if (parsed == null) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.notResponsibility,
        '',
      );
    }

    final scope = _currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) return _unavailable;
    final editor = await _getEditor();
    final state = await editor.load(scope);
    final model = state?.model;
    if (model == null || model.accountScopeId != scope) return _unavailable;

    final resolution = _resolveSubject(model, parsed.subjectText);
    if (resolution.person != null) {
      final complete = parsed.copyWith(
        subjectPersonId: resolution.person!.id,
        subjectDisplayName: resolution.person!.displayName,
      );
      _pending = complete;
      return complete.hasCompleteTimeRange
          ? RecurringResponsibilityConversationResult(
              RecurringResponsibilityConversationResultType.confirmation,
              complete.confirmationQuestion,
            )
          : RecurringResponsibilityConversationResult(
              RecurringResponsibilityConversationResultType.clarification,
              complete.timeQuestion,
            );
    }

    final draft = parsed.copyWith(
      candidatePersonIds: resolution.candidates.map((item) => item.id).toList(),
    );
    _pending = draft;
    final names = resolution.candidates
        .map((item) => item.displayName?.trim() ?? '')
        .where((item) => item.isNotEmpty)
        .join(' ou ');
    return RecurringResponsibilityConversationResult(
      RecurringResponsibilityConversationResultType.clarification,
      names.isEmpty
          ? 'De quelle personne parles-tu ?'
          : 'De qui parles-tu : $names ?',
    );
  }

  Future<RecurringResponsibilityConversationResult> _resolveSchoolTransition(
    String message,
    _SchoolTransitionProposal proposal,
  ) async {
    final answer = _answers.classify(message);
    if (answer == ConversationAnswer.ambiguous) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.clarification,
        'Dis-moi simplement oui ou non.',
      );
    }
    final scope = _currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) return _unavailable;
    final editor = await _getEditor();
    final state = await editor.load(scope);
    final model = state?.model;
    if (model == null || model.accountScopeId != scope) return _unavailable;

    final responsibilities = answer == ConversationAnswer.positive
        ? _confirmedSchoolTransitionResponsibilities(
            editor: editor,
            model: model,
            proposal: proposal,
          )
        : const <HumanResponsibility>[];
    final result = await editor.commit(
      accountScopeId: scope,
      actionType: ActionType.modifyResponsibility,
      actionOrigin: ActionOrigin.explicitUserConfirmation,
      transform: (current) {
        if (answer == ConversationAnswer.positive) {
          return current.copyWith(
            responsibilities: [
              ...current.responsibilities,
              ...responsibilities,
            ],
          );
        }
        return current.copyWith(
          persons: current.persons
              .map(
                (person) => person.id == proposal.subjectPersonId
                    ? person.copyWith(
                        customFields: {
                          ...person.customFields,
                          proposal.rejectionField: true,
                        },
                      )
                    : person,
              )
              .toList(growable: false),
        );
      },
    );
    if (result.status != HumanModelEditStatus.success &&
        result.status != HumanModelEditStatus.pendingSync) {
      return _unavailable;
    }
    _pendingSchoolTransition = null;
    if (answer == ConversationAnswer.negative) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.cancelled,
        'D’accord, je ne réserverai pas ce trajet dans ton planning.',
      );
    }
    if (result.status == HumanModelEditStatus.pendingSync) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.saved,
        'C’est noté sur ce téléphone. Je prendrai ce trajet en compte et '
        'je le synchroniserai dès que la connexion sera disponible.',
      );
    }
    return const RecurringResponsibilityConversationResult(
      RecurringResponsibilityConversationResultType.saved,
      'C’est noté. Je penserai désormais au temps nécessaire pour ce trajet.',
    );
  }

  static List<HumanResponsibility> _confirmedSchoolTransitionResponsibilities({
    required HumanModelEditService editor,
    required HumanModel model,
    required _SchoolTransitionProposal proposal,
  }) {
    return proposal.ranges
        .map(
          (range) => editor.newResponsibility(
            accountScopeId: model.accountScopeId,
            responsiblePersonId: model.primaryPersonId,
            subjectPersonId: proposal.subjectPersonId,
            type: HumanResponsibilityTypes.transport,
            customType: proposal.planningLabel,
            scope: proposal.scopeFor(range),
            recurringPlanningConsequence: HumanRecurringPlanningConsequence(
              type: HumanPlanningConsequenceTypes.transport,
              weekdays: range.weekdays,
              startTime: range.blockingStart,
              endTime: range.blockingEnd,
            ),
          ),
        )
        .toList(growable: false);
  }

  static Future<void> _synchronizeConfirmedSchoolTransition({
    required HumanModelEditService editor,
    required HumanModel model,
    required String subjectPersonId,
    required String subjectDisplayName,
    required List<_SchoolTransitionRange> ranges,
    required _SchoolTransitionKind kind,
  }) async {
    if (ranges.isEmpty) return;
    final existing = model.responsibilities
        .where(
          (responsibility) =>
              responsibility.status == HumanRecordStatus.active &&
              responsibility.responsiblePersonId == model.primaryPersonId &&
              responsibility.subjectPersonId == subjectPersonId &&
              responsibility.type == HumanResponsibilityTypes.transport &&
              (responsibility.scope ?? '').startsWith(
                kind.scopePrefix,
              ),
        )
        .toList(growable: false);
    if (existing.isEmpty) return;

    final proposal = _SchoolTransitionProposal(
      kind: kind,
      subjectPersonId: subjectPersonId,
      subjectDisplayName: subjectDisplayName,
      ranges: ranges,
    );
    if (_schoolTransitionTimingMatches(existing, proposal)) return;

    final replacements = <HumanResponsibility>[];
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      final consequence = HumanRecurringPlanningConsequence(
        type: HumanPlanningConsequenceTypes.transport,
        weekdays: range.weekdays,
        startTime: range.blockingStart,
        endTime: range.blockingEnd,
      );
      if (index < existing.length) {
        replacements.add(
          existing[index].copyWith(
            type: HumanResponsibilityTypes.transport,
            customType: proposal.planningLabel,
            scope: proposal.scopeFor(range),
            clearPlanningConsequence: true,
            recurringPlanningConsequence: consequence,
            status: HumanRecordStatus.active,
          ),
        );
      } else {
        replacements.add(
          editor.newResponsibility(
            accountScopeId: model.accountScopeId,
            responsiblePersonId: model.primaryPersonId,
            subjectPersonId: subjectPersonId,
            type: HumanResponsibilityTypes.transport,
            customType: proposal.planningLabel,
            scope: proposal.scopeFor(range),
            recurringPlanningConsequence: consequence,
          ),
        );
      }
    }
    final replacedIds = existing.map((item) => item.id).toSet();
    await editor.commit(
      accountScopeId: model.accountScopeId,
      actionType: ActionType.modifyResponsibility,
      actionOrigin: ActionOrigin.structuredContinuation,
      transform: (current) => current.copyWith(
        responsibilities: [
          ...current.responsibilities.where(
            (item) => !replacedIds.contains(item.id),
          ),
          ...replacements,
        ],
      ),
    );
  }

  static bool _schoolTransitionTimingMatches(
    List<HumanResponsibility> existing,
    _SchoolTransitionProposal proposal,
  ) {
    if (existing.length != proposal.ranges.length) return false;
    for (final range in proposal.ranges) {
      final matches = existing.where((responsibility) {
        final consequence = responsibility.recurringPlanningConsequence;
        return responsibility.customType == proposal.planningLabel &&
            responsibility.scope == proposal.scopeFor(range) &&
            consequence?.type == HumanPlanningConsequenceTypes.transport &&
            _sameIntegers(consequence?.weekdays ?? const [], range.weekdays) &&
            consequence?.startTime == range.blockingStart &&
            consequence?.endTime == range.blockingEnd &&
            consequence?.blocksResponsiblePerson == true;
      });
      if (matches.length != 1) return false;
    }
    return true;
  }

  Future<RecurringResponsibilityConversationResult> _completeClarification(
    String message,
    _RecurringResponsibilityDraft pending,
  ) async {
    final scope = _currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) return _unavailable;
    final editor = await _getEditor();
    final state = await editor.load(scope);
    final model = state?.model;
    if (model == null || model.accountScopeId != scope) return _unavailable;

    var updated = pending;
    if (updated.subjectPersonId == null) {
      final allowed = updated.candidatePersonIds.isEmpty
          ? model.persons
          : model.persons.where(
              (person) => updated.candidatePersonIds.contains(person.id),
            );
      final resolution = _matchNamedPerson(
        allowed.where((person) => person.id != model.primaryPersonId),
        message,
      );
      if (resolution == null) {
        return const RecurringResponsibilityConversationResult(
          RecurringResponsibilityConversationResultType.clarification,
          'Je ne reconnais pas encore cette personne dans ton profil. '
          'Tu peux me donner son prénom exact.',
        );
      }
      updated = updated.copyWith(
        subjectPersonId: resolution.id,
        subjectDisplayName: resolution.displayName,
      );
    }

    if (!updated.hasCompleteTimeRange) {
      final range = _RecurringResponsibilityParser.timeRange(message);
      if (range == null) {
        _pending = updated;
        return RecurringResponsibilityConversationResult(
          RecurringResponsibilityConversationResultType.clarification,
          updated.timeQuestion,
        );
      }
      updated = updated.copyWith(
        startTime: range.start,
        endTime: range.end,
      );
    }

    _pending = updated;
    return RecurringResponsibilityConversationResult(
      RecurringResponsibilityConversationResultType.confirmation,
      updated.confirmationQuestion,
    );
  }

  Future<RecurringResponsibilityConversationResult> _resolveConfirmation(
    String message,
    _RecurringResponsibilityDraft pending,
  ) async {
    final answer = _answers.classify(message);
    if (answer == ConversationAnswer.negative) {
      _pending = null;
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.cancelled,
        'D’accord, je ne l’ajoute pas.',
      );
    }
    if (answer != ConversationAnswer.positive) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.clarification,
        'Dis-moi simplement oui ou non.',
      );
    }

    final scope = _currentAccountScopeId()?.trim() ?? '';
    if (scope.isEmpty) return _unavailable;
    final editor = await _getEditor();
    final state = await editor.load(scope);
    final model = state?.model;
    if (model == null || model.accountScopeId != scope) return _unavailable;
    if (pending.subjectPersonId == null || !pending.hasCompleteTimeRange) {
      _pending = null;
      return _unavailable;
    }

    if (_containsExactResponsibility(model, pending)) {
      _pending = null;
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.saved,
        'C’est déjà pris en compte dans ton organisation.',
      );
    }

    final responsibility = editor.newResponsibility(
      accountScopeId: scope,
      responsiblePersonId: model.primaryPersonId,
      subjectPersonId: pending.subjectPersonId!,
      type: pending.responsibilityType,
      scope: pending.canonicalScope,
      recurringPlanningConsequence: HumanRecurringPlanningConsequence(
        type: pending.consequenceType,
        weekdays: pending.weekdays,
        startTime: pending.startTime!,
        endTime: pending.endTime!,
      ),
    );
    final result = await editor.commit(
      accountScopeId: scope,
      actionType: ActionType.modifyResponsibility,
      actionOrigin: ActionOrigin.explicitUserConfirmation,
      transform: (current) => current.copyWith(
        responsibilities: [...current.responsibilities, responsibility],
      ),
    );
    if (result.status != HumanModelEditStatus.success &&
        result.status != HumanModelEditStatus.pendingSync) {
      return _unavailable;
    }
    _pending = null;
    if (result.status == HumanModelEditStatus.pendingSync) {
      return const RecurringResponsibilityConversationResult(
        RecurringResponsibilityConversationResultType.saved,
        'C’est gardé sur ce téléphone. Je synchroniserai cette information '
        'dès que la connexion sera disponible.',
      );
    }
    return const RecurringResponsibilityConversationResult(
      RecurringResponsibilityConversationResultType.saved,
      'C’est noté. Je prendrai ce créneau en compte dans ton organisation.',
    );
  }

  Future<HumanModelEditService> _getEditor() async =>
      _editor ??= await _loadEditor();

  static bool _containsExactResponsibility(
    HumanModel model,
    _RecurringResponsibilityDraft draft,
  ) =>
      model.responsibilities.any((responsibility) {
        final recurring = responsibility.recurringPlanningConsequence;
        return responsibility.status == HumanRecordStatus.active &&
            responsibility.responsiblePersonId == model.primaryPersonId &&
            responsibility.subjectPersonId == draft.subjectPersonId &&
            responsibility.type == draft.responsibilityType &&
            recurring?.type == draft.consequenceType &&
            _sameIntegers(recurring?.weekdays ?? const [], draft.weekdays) &&
            recurring?.startTime == draft.startTime &&
            recurring?.endTime == draft.endTime;
      });

  static _SubjectResolution _resolveSubject(
    HumanModel model,
    String subjectText,
  ) {
    final activePeople = model.persons.where(
      (person) =>
          person.id != model.primaryPersonId &&
          person.status == HumanPersonStatus.active,
    );
    final named = _matchNamedPerson(activePeople, subjectText);
    if (named != null) return _SubjectResolution(person: named);

    final relationTypes = _relationTypesFor(subjectText);
    if (relationTypes.isEmpty) return const _SubjectResolution();
    final candidateIds = model.relationships
        .where((relationship) =>
            relationship.sourcePersonId == model.primaryPersonId &&
            relationship.status == HumanRecordStatus.active &&
            relationTypes.contains(relationship.type))
        .map((relationship) => relationship.targetPersonId)
        .toSet();
    final candidates = activePeople
        .where((person) => candidateIds.contains(person.id))
        .toList(growable: false);
    return candidates.length == 1
        ? _SubjectResolution(person: candidates.single)
        : _SubjectResolution(candidates: candidates);
  }

  static HumanPerson? _personForChild(
    HumanModel model,
    ChildProfile child,
  ) {
    final id = child.humanPersonId.trim();
    if (id.isNotEmpty) {
      final matches = model.persons
          .where((person) =>
              person.id == id && person.status == HumanPersonStatus.active)
          .toList(growable: false);
      if (matches.length == 1) return matches.single;
    }
    return _matchNamedPerson(
      model.persons.where((person) =>
          person.id != model.primaryPersonId &&
          person.status == HumanPersonStatus.active),
      child.firstName,
    );
  }

  static bool _hasSchoolTransitionDecision(
    HumanModel model,
    String subjectPersonId,
    _SchoolTransitionKind kind,
    List<_SchoolTransitionRange> ranges,
  ) {
    HumanPerson? person;
    for (final candidate in model.persons) {
      if (candidate.id == subjectPersonId) {
        person = candidate;
        break;
      }
    }
    if (person?.customFields[kind.rejectionField] == true) {
      return true;
    }
    return model.responsibilities.any((responsibility) =>
        responsibility.status == HumanRecordStatus.active &&
        responsibility.responsiblePersonId == model.primaryPersonId &&
        responsibility.subjectPersonId == subjectPersonId &&
        responsibility.type == HumanResponsibilityTypes.transport &&
        ((responsibility.scope ?? '').startsWith(kind.scopePrefix) ||
            kind.matchesExplicitLabel(responsibility.customType) ||
            _matchesTransitionTiming(
              responsibility.recurringPlanningConsequence,
              ranges,
            )) &&
        (responsibility.evidence.confirmation ==
                HumanConfirmationStatus.confirmed ||
            responsibility.evidence.confirmation ==
                HumanConfirmationStatus.rejected));
  }

  static bool _matchesTransitionTiming(
    HumanRecurringPlanningConsequence? consequence,
    List<_SchoolTransitionRange> ranges,
  ) {
    if (consequence == null) return false;
    final consequenceStart =
        _SchoolTransitionRange.minutes(consequence.startTime);
    final consequenceEnd = _SchoolTransitionRange.minutes(consequence.endTime);
    for (final range in ranges) {
      if (!range.weekdays.any(consequence.weekdays.contains)) continue;
      final boundary = _SchoolTransitionRange.minutes(range.boundaryTime);
      if (consequenceStart <= boundary && consequenceEnd >= boundary) {
        return true;
      }
    }
    return false;
  }

  static HumanPerson? _matchNamedPerson(
    Iterable<HumanPerson> people,
    String text,
  ) {
    final normalized = _normalize(text);
    final matches = people.where((person) {
      final name = _normalize(person.displayName ?? '');
      return name.isNotEmpty &&
          RegExp('(?:^|\\s)${RegExp.escape(name)}(?:\\s|\$)')
              .hasMatch(normalized);
    }).toList(growable: false)
      ..sort((left, right) => (right.displayName?.length ?? 0)
          .compareTo(left.displayName?.length ?? 0));
    return matches.length == 1 ? matches.single : null;
  }

  static Set<String> _relationTypesFor(String value) {
    final text = _normalize(value);
    if (RegExp(r'\b(?:mon|ma)\s+(?:fils|fille|enfant)\b').hasMatch(text)) {
      return {HumanRelationshipTypes.child};
    }
    if (RegExp(r'\b(?:mon|ma)\s+(?:mari|femme|conjoint|conjointe|partenaire)\b')
        .hasMatch(text)) {
      return {
        HumanRelationshipTypes.partner,
        HumanRelationshipTypes.spouse,
      };
    }
    if (RegExp(r'\b(?:mon pere|ma mere|mon parent)\b').hasMatch(text)) {
      return {HumanRelationshipTypes.parent};
    }
    if (RegExp(r'\b(?:mon frere|ma soeur)\b').hasMatch(text)) {
      return {HumanRelationshipTypes.sibling};
    }
    return const {};
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâ]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _sameIntegers(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    final sortedLeft = [...left]..sort();
    final sortedRight = [...right]..sort();
    for (var index = 0; index < sortedLeft.length; index++) {
      if (sortedLeft[index] != sortedRight[index]) return false;
    }
    return true;
  }

  static const _unavailable = RecurringResponsibilityConversationResult(
    RecurringResponsibilityConversationResultType.unavailable,
    'Je n’ai pas pu enregistrer cette responsabilité pour le moment. '
    'Tu peux réessayer dans un instant.',
  );

  static const _notResponsibility = RecurringResponsibilityConversationResult(
    RecurringResponsibilityConversationResultType.notResponsibility,
    '',
  );
}

final class _RecurringResponsibilityParser {
  static const _dayNames = <String, int>{
    'lundi': DateTime.monday,
    'mardi': DateTime.tuesday,
    'mercredi': DateTime.wednesday,
    'jeudi': DateTime.thursday,
    'vendredi': DateTime.friday,
    'samedi': DateTime.saturday,
    'dimanche': DateTime.sunday,
  };

  static _RecurringResponsibilityDraft? parse(String input) {
    final text = _normalize(input);
    if (text.contains('?') ||
        RegExp(r'\b(?:peut etre|avant|parfois|eventuellement)\b')
            .hasMatch(text)) {
      return null;
    }
    final kind = _kind(text);
    if (kind == null || !_isRecurring(text)) return null;
    final days = _weekdays(text);
    if (days.isEmpty) return null;
    final subject = _subject(text, kind.verbPattern);
    final range = timeRange(input);
    return _RecurringResponsibilityDraft(
      responsibilityType: kind.responsibilityType,
      consequenceType: kind.consequenceType,
      actionLabel: kind.actionLabel,
      subjectText: subject,
      weekdays: days,
      startTime: range?.start,
      endTime: range?.end,
    );
  }

  static _TimeRange? timeRange(String input) {
    final text = RoutineTimeExpressionNormalizer.normalizeForAnalysis(input);
    final times = RegExp(r'\b(\d{2}):(\d{2})\b')
        .allMatches(text)
        .map((match) => '${match.group(1)}:${match.group(2)}')
        .toList(growable: false);
    if (times.length < 2 || times[0] == times[1]) return null;
    return _TimeRange(times[0], times[1]);
  }

  static _ResponsibilityKind? _kind(String text) {
    const kinds = [
      _ResponsibilityKind(
        verbPattern: r'(?:depos\w*|emmen\w*|amen\w*|ramen\w*|'
            r'recuper\w*|vais chercher|va chercher)',
        responsibilityType: HumanResponsibilityTypes.transport,
        consequenceType: HumanPlanningConsequenceTypes.transport,
        actionLabel: 'tu assures le trajet pour',
      ),
      _ResponsibilityKind(
        verbPattern: r'accompagn\w*',
        responsibilityType: HumanResponsibilityTypes.accompaniment,
        consequenceType: HumanPlanningConsequenceTypes.accompaniment,
        actionLabel: 'tu accompagnes',
      ),
      _ResponsibilityKind(
        verbPattern: r'attend\w*',
        responsibilityType: HumanResponsibilityTypes.accompaniment,
        consequenceType: HumanPlanningConsequenceTypes.waiting,
        actionLabel: 'tu attends',
      ),
      _ResponsibilityKind(
        verbPattern: r'(?:gard\w*|m occupe de|prends soin de)',
        responsibilityType: HumanResponsibilityTypes.care,
        consequenceType: HumanPlanningConsequenceTypes.care,
        actionLabel: 'tu t’occupes de',
      ),
      _ResponsibilityKind(
        verbPattern: r'aid\w*',
        responsibilityType: HumanResponsibilityTypes.dailyAssistance,
        consequenceType: HumanPlanningConsequenceTypes.dailyAssistance,
        actionLabel: 'tu aides',
      ),
    ];
    for (final kind in kinds) {
      if (RegExp(
        '\\b(?:je|j)\\s+(?:(?:dois|vais)\\s+)?${kind.verbPattern}\\b',
      ).hasMatch(text)) {
        return kind;
      }
    }
    return null;
  }

  static bool _isRecurring(String text) => RegExp(
        r'\b(?:tous les|toutes les|chaque|du lundi au vendredi|tous les jours)\b',
      ).hasMatch(text);

  static List<int> _weekdays(String text) {
    if (text.contains('tous les jours')) {
      return const [1, 2, 3, 4, 5, 6, 7];
    }
    if (text.contains('du lundi au vendredi')) {
      return const [1, 2, 3, 4, 5];
    }
    final days = <int>[];
    for (final entry in _dayNames.entries) {
      if (RegExp('\\b${entry.key}s?\\b').hasMatch(text)) {
        days.add(entry.value);
      }
    }
    return days..sort();
  }

  static String _subject(String text, String verbPattern) {
    final match = RegExp(
      '\\b(?:je|j)\\s+(?:(?:dois|vais)\\s+)?(?:$verbPattern)\\s+(.+?)(?='
      r'\s+(?:tous les|toutes les|chaque|du lundi au vendredi|tous les jours|'
      r'de\s+\d|entre\s+\d)|[,.!?]|$)',
    ).firstMatch(text);
    return match?.group(1)?.trim() ?? '';
  }

  static String _normalize(String value) =>
      RecurringResponsibilityConversationService._normalize(value)
          .replaceAll("'", ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}

final class _RecurringResponsibilityDraft {
  const _RecurringResponsibilityDraft({
    required this.responsibilityType,
    required this.consequenceType,
    required this.actionLabel,
    required this.subjectText,
    required this.weekdays,
    this.startTime,
    this.endTime,
    this.subjectPersonId,
    this.subjectDisplayName,
    this.candidatePersonIds = const [],
  });

  final String responsibilityType;
  final String consequenceType;
  final String actionLabel;
  final String subjectText;
  final List<int> weekdays;
  final String? startTime;
  final String? endTime;
  final String? subjectPersonId;
  final String? subjectDisplayName;
  final List<String> candidatePersonIds;

  bool get hasCompleteTimeRange => startTime != null && endTime != null;
  bool get isComplete => subjectPersonId != null && hasCompleteTimeRange;

  String get canonicalScope =>
      'regular:$consequenceType:${weekdays.join(',')}:$startTime-$endTime';

  String get timeQuestion =>
      'De quelle heure à quelle heure $actionLabel ${_personLabel()} ?';

  String get confirmationQuestion =>
      'J’ai compris : $actionLabel ${_personLabel()} ${_daysLabel()} '
      'de ${_displayTime(startTime!)} à ${_displayTime(endTime!)}. '
      'Je prends ce créneau en compte dans ton organisation ?';

  _RecurringResponsibilityDraft copyWith({
    String? startTime,
    String? endTime,
    String? subjectPersonId,
    String? subjectDisplayName,
    List<String>? candidatePersonIds,
  }) =>
      _RecurringResponsibilityDraft(
        responsibilityType: responsibilityType,
        consequenceType: consequenceType,
        actionLabel: actionLabel,
        subjectText: subjectText,
        weekdays: weekdays,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        subjectPersonId: subjectPersonId ?? this.subjectPersonId,
        subjectDisplayName: subjectDisplayName ?? this.subjectDisplayName,
        candidatePersonIds: candidatePersonIds ?? this.candidatePersonIds,
      );

  String _personLabel() {
    final name = subjectDisplayName?.trim() ?? '';
    return name.isNotEmpty ? name : subjectText;
  }

  String _daysLabel() {
    if (weekdays.length == 7) return 'tous les jours';
    if (_sameWeekdays(weekdays, const [1, 2, 3, 4, 5])) {
      return 'du lundi au vendredi';
    }
    const labels = {
      1: 'lundi',
      2: 'mardi',
      3: 'mercredi',
      4: 'jeudi',
      5: 'vendredi',
      6: 'samedi',
      7: 'dimanche',
    };
    final values = weekdays.map((day) => labels[day]!).toList();
    if (values.length == 1) return 'chaque ${values.single}';
    return 'chaque ${values.sublist(0, values.length - 1).join(', ')} et '
        '${values.last}';
  }

  static bool _sameWeekdays(List<int> left, List<int> right) =>
      RecurringResponsibilityConversationService._sameIntegers(left, right);

  static String _displayTime(String value) {
    final parts = value.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return minute == 0
        ? '$hour h'
        : '$hour h ${minute.toString().padLeft(2, '0')}';
  }
}

final class _ResponsibilityKind {
  const _ResponsibilityKind({
    required this.verbPattern,
    required this.responsibilityType,
    required this.consequenceType,
    required this.actionLabel,
  });

  final String verbPattern;
  final String responsibilityType;
  final String consequenceType;
  final String actionLabel;
}

final class _SubjectResolution {
  const _SubjectResolution({this.person, this.candidates = const []});

  final HumanPerson? person;
  final List<HumanPerson> candidates;
}

final class _TimeRange {
  const _TimeRange(this.start, this.end);

  final String start;
  final String end;
}

enum _SchoolTransitionKind { dropoff, pickup }

extension on _SchoolTransitionKind {
  String get scopePrefix => switch (this) {
        _SchoolTransitionKind.dropoff => 'schoolDropoff:',
        _SchoolTransitionKind.pickup => 'schoolPickup:',
      };

  String get rejectionField => switch (this) {
        _SchoolTransitionKind.dropoff => 'schoolDropoffProposalRejected',
        _SchoolTransitionKind.pickup => 'schoolPickupProposalRejected',
      };

  bool matchesExplicitLabel(String? value) {
    final normalized =
        RecurringResponsibilityConversationService._normalize(value ?? '');
    return switch (this) {
      _SchoolTransitionKind.dropoff =>
        RegExp(r'\b(?:depos\w*|amen\w*)\b').hasMatch(normalized),
      _SchoolTransitionKind.pickup =>
        RegExp(r'\b(?:recuper\w*|cherch\w*)\b').hasMatch(normalized),
    };
  }
}

final class _SchoolTransitionProposal {
  const _SchoolTransitionProposal({
    required this.kind,
    required this.subjectPersonId,
    required this.subjectDisplayName,
    required this.ranges,
  });

  final _SchoolTransitionKind kind;
  final String subjectPersonId;
  final String subjectDisplayName;
  final List<_SchoolTransitionRange> ranges;

  String get rejectionField => kind.rejectionField;

  String get question => switch (kind) {
        _SchoolTransitionKind.dropoff =>
          'Avant de vérifier ce créneau, j’ai juste besoin de savoir une '
              'chose : est-ce que c’est généralement toi qui déposes '
              '$subjectDisplayName à l’école ?',
        _SchoolTransitionKind.pickup =>
          'Avant de vérifier ce créneau, j’ai juste besoin de savoir une '
              'chose : est-ce que c’est généralement toi qui récupères '
              '$subjectDisplayName à la sortie de l’école ?',
      };
  String get planningLabel => switch (kind) {
        _SchoolTransitionKind.dropoff =>
          'Déposer $subjectDisplayName à l’école',
        _SchoolTransitionKind.pickup =>
          'Récupérer $subjectDisplayName à la sortie de l’école',
      };
  String scopeFor(_SchoolTransitionRange range) =>
      '${kind.scopePrefix}$subjectPersonId:${range.weekdays.join(',')}:'
      '${range.boundaryTime}:${range.travelMinutes}';
}

final class _SchoolTransitionRange {
  const _SchoolTransitionRange({
    required this.weekdays,
    required this.boundaryTime,
    required this.travelMinutes,
  });

  final List<int> weekdays;
  final String boundaryTime;
  final int travelMinutes;

  String get protectedStart => _shift(boundaryTime, -travelMinutes);
  String get protectedEnd => _shift(boundaryTime, travelMinutes);
  String get blockingStart => protectedStart;
  String get blockingEnd => travelMinutes > 0
      ? protectedEnd
      : _shift(boundaryTime, _minimumTransitionMinutes);

  // A confirmed responsibility at a known clock time must remain visible to
  // planning even when the commute duration is not known yet. This one-minute
  // marker represents the exact transition instant, not an invented journey.
  static const int _minimumTransitionMinutes = 1;

  bool isRelevantTo({required int weekday, required String time}) {
    if (!weekdays.contains(weekday)) return false;
    final requested = minutes(time);
    if (travelMinutes <= 0) return requested == minutes(boundaryTime);
    return requested >= minutes(protectedStart) &&
        requested <= minutes(protectedEnd);
  }

  static _SchoolTransitionRange? fromProfile(
    TimeRangeModel range,
    _SchoolTransitionKind kind,
  ) {
    final weekdays = SchoolScheduleMetadataService.daysFromRange(range)
        .map(_weekday)
        .whereType<int>()
        .toSet()
        .toList(growable: false)
      ..sort();
    final boundary = canonicalTime(
      kind == _SchoolTransitionKind.dropoff ? range.startTime : range.endTime,
    );
    if (weekdays.isEmpty || boundary == null) return null;
    final travel = int.tryParse(range.travelMinutes.trim()) ?? 0;
    return _SchoolTransitionRange(
      weekdays: weekdays,
      boundaryTime: boundary,
      travelMinutes: travel > 0 ? travel : 0,
    );
  }

  static List<_SchoolTransitionRange> boundaryPerWeekday(
    Iterable<_SchoolTransitionRange> ranges,
    _SchoolTransitionKind kind,
  ) {
    final selected = <int, _SchoolTransitionRange>{};
    for (final range in ranges) {
      for (final weekday in range.weekdays) {
        final current = selected[weekday];
        if (current == null ||
            (kind == _SchoolTransitionKind.dropoff
                ? minutes(range.boundaryTime) < minutes(current.boundaryTime)
                : minutes(range.boundaryTime) >
                    minutes(current.boundaryTime))) {
          selected[weekday] = _SchoolTransitionRange(
            weekdays: [weekday],
            boundaryTime: range.boundaryTime,
            travelMinutes: range.travelMinutes,
          );
        }
      }
    }
    final grouped = <String, List<int>>{};
    for (final entry in selected.entries) {
      final range = entry.value;
      final key = '${range.boundaryTime}|${range.travelMinutes}';
      grouped.putIfAbsent(key, () => []).add(entry.key);
    }
    final result = grouped.entries.map((entry) {
      final parts = entry.key.split('|');
      final weekdays = entry.value..sort();
      return _SchoolTransitionRange(
        weekdays: weekdays,
        boundaryTime: parts[0],
        travelMinutes: int.parse(parts[1]),
      );
    }).toList(growable: false)
      ..sort((left, right) => left.weekdays.first.compareTo(
            right.weekdays.first,
          ));
    return result;
  }

  static int? _weekday(String value) {
    final normalized = RecurringResponsibilityConversationService._normalize(
      value,
    );
    return const {
      'lundi': DateTime.monday,
      'mardi': DateTime.tuesday,
      'mercredi': DateTime.wednesday,
      'jeudi': DateTime.thursday,
      'vendredi': DateTime.friday,
      'samedi': DateTime.saturday,
      'dimanche': DateTime.sunday,
    }[normalized];
  }

  static String? canonicalTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static String _shift(String value, int delta) {
    final parts = value.split(':');
    final minutes =
        (int.parse(parts[0]) * 60 + int.parse(parts[1]) + delta) % (24 * 60);
    final normalized = minutes < 0 ? minutes + 24 * 60 : minutes;
    return '${(normalized ~/ 60).toString().padLeft(2, '0')}:'
        '${(normalized % 60).toString().padLeft(2, '0')}';
  }

  static int minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}
