import 'dart:collection';

enum StructuredScheduleDocumentKind { image, pdf }

enum StructuredScheduleTarget {
  event,
  workSchedule,
  schoolSchedule,
  activitySchedule,
  otherSchedule,
}

enum StructuredScheduleTemporalKind { dated, recurringWeekly }

enum StructuredScheduleConfidence { high, medium, low }

enum StructuredScheduleUncertainty {
  subject,
  title,
  date,
  weekdays,
  startTime,
  endTime,
  place,
  recurrence,
}

enum StructuredScheduleProposalState {
  pendingReview,
  accepted,
  corrected,
  rejected,
}

enum StructuredScheduleReviewState { needsReview, readyToApply }

final class StructuredScheduleImportException implements Exception {
  const StructuredScheduleImportException(this.code);

  final String code;

  @override
  String toString() => 'StructuredScheduleImportException($code)';
}

/// One typed line extracted from an image or PDF.
///
/// The proposal deliberately contains no file path, image bytes, PDF bytes or
/// raw OCR text. Only the structured facts needed for user review may cross
/// this boundary.
final class StructuredScheduleProposal {
  static const int currentSchemaVersion = 1;

  StructuredScheduleProposal({
    this.schemaVersion = currentSchemaVersion,
    required this.proposalId,
    required this.target,
    required this.temporalKind,
    required this.title,
    this.subjectEntityId,
    this.subjectLabel,
    this.dateIso,
    List<int> weekdays = const [],
    this.startTime,
    this.endTime,
    this.place,
    required this.confidence,
    List<StructuredScheduleUncertainty> uncertainties = const [],
    this.state = StructuredScheduleProposalState.pendingReview,
  })  : weekdays = UnmodifiableListView(List<int>.of(weekdays)..sort()),
        uncertainties = UnmodifiableListView(
          List<StructuredScheduleUncertainty>.of(uncertainties)
            ..sort((a, b) => a.index.compareTo(b.index)),
        ) {
    _validate();
  }

  final int schemaVersion;
  final String proposalId;
  final StructuredScheduleTarget target;
  final StructuredScheduleTemporalKind temporalKind;
  final String title;
  final String? subjectEntityId;
  final String? subjectLabel;
  final String? dateIso;
  final List<int> weekdays;
  final String? startTime;
  final String? endTime;
  final String? place;
  final StructuredScheduleConfidence confidence;
  final List<StructuredScheduleUncertainty> uncertainties;
  final StructuredScheduleProposalState state;

  factory StructuredScheduleProposal.fromJson(Map<String, dynamic> json) {
    try {
      final weekdaysValue = json['weekdays'];
      final uncertaintiesValue = json['uncertainties'];
      if (weekdaysValue is! List || uncertaintiesValue is! List) {
        throw const FormatException('invalid_schedule_proposal_lists');
      }
      return StructuredScheduleProposal(
        schemaVersion: json['schemaVersion'] as int,
        proposalId: json['proposalId'] as String,
        target: _enumByName(StructuredScheduleTarget.values, json['target']),
        temporalKind: _enumByName(
          StructuredScheduleTemporalKind.values,
          json['temporalKind'],
        ),
        title: json['title'] as String,
        subjectEntityId: json['subjectEntityId'] as String?,
        subjectLabel: json['subjectLabel'] as String?,
        dateIso: json['dateIso'] as String?,
        weekdays: weekdaysValue.cast<int>(),
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        place: json['place'] as String?,
        confidence: _enumByName(
          StructuredScheduleConfidence.values,
          json['confidence'],
        ),
        uncertainties: uncertaintiesValue
            .map(
              (value) => _enumByName(
                StructuredScheduleUncertainty.values,
                value,
              ),
            )
            .toList(),
        state: _enumByName(
          StructuredScheduleProposalState.values,
          json['state'],
        ),
      );
    } on StructuredScheduleImportException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid_structured_schedule_proposal', error);
    }
  }

  bool get isComplete =>
      uncertainties.isEmpty &&
      subjectEntityId != null &&
      subjectLabel != null &&
      _hasRequiredTemporalFacts;

  bool get isKept =>
      state == StructuredScheduleProposalState.accepted ||
      state == StructuredScheduleProposalState.corrected;

  /// A clock range whose end belongs to the following civil day.
  bool get spansMidnight {
    final startMinutes = _localTimeMinutes(startTime);
    final endMinutes = _localTimeMinutes(endTime);
    return startMinutes != null &&
        endMinutes != null &&
        endMinutes < startMinutes;
  }

  StructuredScheduleProposal copyWith({
    StructuredScheduleTarget? target,
    StructuredScheduleTemporalKind? temporalKind,
    String? title,
    String? subjectEntityId,
    bool clearSubjectEntityId = false,
    String? subjectLabel,
    bool clearSubjectLabel = false,
    String? dateIso,
    bool clearDateIso = false,
    List<int>? weekdays,
    String? startTime,
    bool clearStartTime = false,
    String? endTime,
    bool clearEndTime = false,
    String? place,
    bool clearPlace = false,
    StructuredScheduleConfidence? confidence,
    List<StructuredScheduleUncertainty>? uncertainties,
    StructuredScheduleProposalState? state,
  }) =>
      StructuredScheduleProposal(
        schemaVersion: schemaVersion,
        proposalId: proposalId,
        target: target ?? this.target,
        temporalKind: temporalKind ?? this.temporalKind,
        title: title ?? this.title,
        subjectEntityId: clearSubjectEntityId
            ? null
            : (subjectEntityId ?? this.subjectEntityId),
        subjectLabel:
            clearSubjectLabel ? null : (subjectLabel ?? this.subjectLabel),
        dateIso: clearDateIso ? null : (dateIso ?? this.dateIso),
        weekdays: weekdays ?? this.weekdays,
        startTime: clearStartTime ? null : (startTime ?? this.startTime),
        endTime: clearEndTime ? null : (endTime ?? this.endTime),
        place: clearPlace ? null : (place ?? this.place),
        confidence: confidence ?? this.confidence,
        uncertainties: uncertainties ?? this.uncertainties,
        state: state ?? this.state,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'proposalId': proposalId,
        'target': target.name,
        'temporalKind': temporalKind.name,
        'title': title,
        if (subjectEntityId != null) 'subjectEntityId': subjectEntityId,
        if (subjectLabel != null) 'subjectLabel': subjectLabel,
        if (dateIso != null) 'dateIso': dateIso,
        if (weekdays.isNotEmpty) 'weekdays': weekdays,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (place != null) 'place': place,
        'confidence': confidence.name,
        'uncertainties': uncertainties.map((item) => item.name).toList(),
        'state': state.name,
      };

  bool get _hasRequiredTemporalFacts =>
      switch (temporalKind) {
        StructuredScheduleTemporalKind.dated =>
          dateIso != null && weekdays.isEmpty,
        StructuredScheduleTemporalKind.recurringWeekly =>
          dateIso == null && weekdays.isNotEmpty,
      } &&
      startTime != null &&
      endTime != null;

  void _validate() {
    final startMinutes = _localTimeMinutes(startTime);
    final endMinutes = _localTimeMinutes(endTime);
    final hasValidDate = dateIso == null || _parseCivilDate(dateIso!) != null;
    final hasValidWeekdays = weekdays.length <= DateTime.daysPerWeek &&
        weekdays.toSet().length == weekdays.length &&
        weekdays.every(
          (day) => day >= DateTime.monday && day <= DateTime.sunday,
        );
    final hasValidUncertainties =
        uncertainties.toSet().length == uncertainties.length;
    final acceptsIncompleteValue =
        state == StructuredScheduleProposalState.pendingReview ||
            state == StructuredScheduleProposalState.rejected;

    if (schemaVersion != currentSchemaVersion ||
        proposalId.trim().isEmpty ||
        proposalId.length > 160 ||
        title.trim().isEmpty ||
        title.length > 300 ||
        subjectEntityId?.trim().isEmpty == true ||
        (subjectEntityId?.length ?? 0) > 160 ||
        subjectLabel?.trim().isEmpty == true ||
        (subjectLabel?.length ?? 0) > 160 ||
        place?.trim().isEmpty == true ||
        (place?.length ?? 0) > 500 ||
        !hasValidDate ||
        !hasValidWeekdays ||
        !hasValidUncertainties ||
        (startTime != null && startMinutes == null) ||
        (endTime != null && endMinutes == null) ||
        (startMinutes != null &&
            endMinutes != null &&
            endMinutes == startMinutes) ||
        (temporalKind == StructuredScheduleTemporalKind.dated &&
            weekdays.isNotEmpty) ||
        (temporalKind == StructuredScheduleTemporalKind.recurringWeekly &&
            dateIso != null) ||
        (target == StructuredScheduleTarget.event &&
            temporalKind != StructuredScheduleTemporalKind.dated) ||
        ((subjectEntityId == null || subjectLabel == null) &&
            !uncertainties.contains(StructuredScheduleUncertainty.subject)) ||
        (dateIso == null &&
            temporalKind == StructuredScheduleTemporalKind.dated &&
            !uncertainties.contains(StructuredScheduleUncertainty.date)) ||
        (weekdays.isEmpty &&
            temporalKind == StructuredScheduleTemporalKind.recurringWeekly &&
            !uncertainties.contains(StructuredScheduleUncertainty.weekdays)) ||
        (startTime == null &&
            !uncertainties.contains(StructuredScheduleUncertainty.startTime)) ||
        (endTime == null &&
            !uncertainties.contains(StructuredScheduleUncertainty.endTime)) ||
        (confidence == StructuredScheduleConfidence.high &&
            uncertainties.isNotEmpty) ||
        (!acceptsIncompleteValue && !isComplete)) {
      throw const StructuredScheduleImportException(
        'invalid_structured_schedule_proposal',
      );
    }
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) throw const FormatException('invalid_enum_name');
  return values.firstWhere(
    (value) => value.name == name,
    orElse: () => throw FormatException('unknown_enum_name: $name'),
  );
}

/// Reviewable structured result created only after the original source was
/// discarded. This is not an authorization to persist any Event or schedule.
final class StructuredScheduleImportReview {
  static const int currentSchemaVersion = 1;
  static const int maximumProposals = 100;

  StructuredScheduleImportReview({
    this.schemaVersion = currentSchemaVersion,
    required this.importId,
    required this.accountScopeId,
    required this.initiatedForSubjectEntityId,
    required this.initiatedForSubjectLabel,
    required this.documentKind,
    required this.createdAt,
    required this.sourceWasDiscarded,
    required List<StructuredScheduleProposal> proposals,
  }) : proposals = UnmodifiableListView(proposals) {
    if (schemaVersion != currentSchemaVersion ||
        importId.trim().isEmpty ||
        importId.length > 160 ||
        accountScopeId.trim().isEmpty ||
        initiatedForSubjectEntityId.trim().isEmpty ||
        initiatedForSubjectEntityId.length > 160 ||
        initiatedForSubjectLabel.trim().isEmpty ||
        initiatedForSubjectLabel.length > 160 ||
        !createdAt.isUtc ||
        !sourceWasDiscarded ||
        this.proposals.isEmpty ||
        this.proposals.length > maximumProposals ||
        this.proposals.map((item) => item.proposalId).toSet().length !=
            this.proposals.length) {
      throw const StructuredScheduleImportException(
        'invalid_structured_schedule_review',
      );
    }
  }

  final int schemaVersion;
  final String importId;
  final String accountScopeId;
  final String initiatedForSubjectEntityId;
  final String initiatedForSubjectLabel;
  final StructuredScheduleDocumentKind documentKind;
  final DateTime createdAt;
  final bool sourceWasDiscarded;
  final List<StructuredScheduleProposal> proposals;

  StructuredScheduleReviewState get state {
    final hasPending = proposals.any(
      (item) => item.state == StructuredScheduleProposalState.pendingReview,
    );
    final hasKept = proposals.any((item) => item.isKept);
    return !hasPending && hasKept
        ? StructuredScheduleReviewState.readyToApply
        : StructuredScheduleReviewState.needsReview;
  }

  StructuredScheduleImportReview copyWith({
    List<StructuredScheduleProposal>? proposals,
  }) =>
      StructuredScheduleImportReview(
        schemaVersion: schemaVersion,
        importId: importId,
        accountScopeId: accountScopeId,
        initiatedForSubjectEntityId: initiatedForSubjectEntityId,
        initiatedForSubjectLabel: initiatedForSubjectLabel,
        documentKind: documentKind,
        createdAt: createdAt,
        sourceWasDiscarded: sourceWasDiscarded,
        proposals: proposals ?? this.proposals,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'importId': importId,
        'accountScopeId': accountScopeId,
        'initiatedForSubjectEntityId': initiatedForSubjectEntityId,
        'initiatedForSubjectLabel': initiatedForSubjectLabel,
        'documentKind': documentKind.name,
        'createdAt': createdAt.toIso8601String(),
        'sourceWasDiscarded': sourceWasDiscarded,
        'state': state.name,
        'proposals': proposals.map((item) => item.toJson()).toList(),
      };
}

int? _localTimeMinutes(String? value) {
  if (value == null ||
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    return null;
  }
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

DateTime? _parseCivilDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}
