enum RoutineRecurrenceType {
  weekly,
  weekdays,
  biweekly,
  monthlyNthWeekday,
}

enum RoutineStatus { active, cancelled }

enum RoutineProposalState {
  collecting,
  awaitingConfirmation,
  declined,
  committed,
  cancelled,
}

final class RoutineProposal {
  static const currentSchemaVersion = 1;

  RoutineProposal({
    required this.proposalId,
    required this.logicalRequestId,
    required this.accountScopeId,
    required this.state,
    required List<int> days,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.title,
    this.recurrenceType,
    this.startTime,
    this.durationMinutes,
    this.anchorDateIso,
    this.weekOfMonth,
    this.humanPersonId,
    this.locationEntityId,
    this.travelGoMinutes = 0,
    this.travelBackMinutes = 0,
    this.marginMinutes = 0,
    this.schemaVersion = currentSchemaVersion,
  }) : days = List.unmodifiable(List<int>.of(days)..sort()) {
    final complete = isComplete;
    if (proposalId.trim().isEmpty ||
        logicalRequestId.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        title?.trim().isEmpty == true ||
        humanPersonId?.trim().isEmpty == true ||
        locationEntityId?.trim().isEmpty == true ||
        this.days.any((day) => day < 1 || day > 7) ||
        (startTime != null && !RoutineModel._validTime(startTime!)) ||
        (anchorDateIso != null &&
            !RoutineModel._validDateIso(anchorDateIso!)) ||
        (durationMinutes != null && durationMinutes! < 1) ||
        travelGoMinutes < 0 ||
        travelBackMinutes < 0 ||
        marginMinutes < 0 ||
        !createdAt.isUtc ||
        !updatedAt.isUtc ||
        !expiresAt.isUtc ||
        updatedAt.isBefore(createdAt) ||
        !expiresAt.isAfter(createdAt) ||
        schemaVersion != currentSchemaVersion ||
        (state == RoutineProposalState.collecting && complete) ||
        ((state == RoutineProposalState.awaitingConfirmation ||
                state == RoutineProposalState.declined ||
                state == RoutineProposalState.committed) &&
            !complete)) {
      throw const FormatException('invalid_routine_proposal_v1');
    }
  }

  final String proposalId;
  final String logicalRequestId;
  final String accountScopeId;
  final RoutineProposalState state;
  final String? title;
  final RoutineRecurrenceType? recurrenceType;
  final List<int> days;
  final String? startTime;
  final int? durationMinutes;
  final String? anchorDateIso;
  final int? weekOfMonth;
  final String? humanPersonId;
  final String? locationEntityId;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final int schemaVersion;

  bool get isComplete =>
      title != null &&
      recurrenceType != null &&
      (recurrenceType == RoutineRecurrenceType.weekdays || days.isNotEmpty) &&
      startTime != null &&
      durationMinutes != null &&
      (recurrenceType != RoutineRecurrenceType.biweekly ||
          (anchorDateIso != null &&
              RoutineModel._validDateIso(anchorDateIso!))) &&
      (recurrenceType != RoutineRecurrenceType.monthlyNthWeekday ||
          (days.length == 1 &&
              (weekOfMonth == -1 ||
                  (weekOfMonth != null &&
                      weekOfMonth! >= 1 &&
                      weekOfMonth! <= 5))));

  bool get isTerminal =>
      state == RoutineProposalState.declined ||
      state == RoutineProposalState.committed ||
      state == RoutineProposalState.cancelled;

  bool isExpiredAt(DateTime referenceDate) =>
      !referenceDate.toUtc().isBefore(expiresAt);

  RoutineProposal copyWith({
    RoutineProposalState? state,
    String? title,
    RoutineRecurrenceType? recurrenceType,
    List<int>? days,
    String? startTime,
    int? durationMinutes,
    String? anchorDateIso,
    int? weekOfMonth,
    String? humanPersonId,
    String? locationEntityId,
    DateTime? updatedAt,
  }) =>
      RoutineProposal(
        proposalId: proposalId,
        logicalRequestId: logicalRequestId,
        accountScopeId: accountScopeId,
        state: state ?? this.state,
        title: this.title ?? title,
        recurrenceType: this.recurrenceType ?? recurrenceType,
        days: this.days.isEmpty ? (days ?? const []) : this.days,
        startTime: this.startTime ?? startTime,
        durationMinutes: this.durationMinutes ?? durationMinutes,
        anchorDateIso: this.anchorDateIso ?? anchorDateIso,
        weekOfMonth: this.weekOfMonth ?? weekOfMonth,
        humanPersonId: this.humanPersonId ?? humanPersonId,
        locationEntityId: this.locationEntityId ?? locationEntityId,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
        createdAt: createdAt,
        updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
        expiresAt: expiresAt,
      );

  RoutineModel toRoutine(DateTime at) => RoutineModel(
        id: proposalId,
        accountScopeId: accountScopeId,
        logicalRequestId: logicalRequestId,
        title: title!,
        recurrenceType: recurrenceType!,
        days: days,
        startTime: startTime!,
        durationMinutes: durationMinutes!,
        anchorDateIso: anchorDateIso,
        weekOfMonth: weekOfMonth,
        humanPersonId: humanPersonId,
        locationEntityId: locationEntityId,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
        createdAt: at.toUtc(),
        updatedAt: at.toUtc(),
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'proposalId': proposalId,
        'logicalRequestId': logicalRequestId,
        'accountScopeId': accountScopeId,
        'state': state.name,
        if (title != null) 'title': title,
        if (recurrenceType != null) 'recurrenceType': recurrenceType!.name,
        'days': days,
        if (startTime != null) 'startTime': startTime,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'anchorDateIso': anchorDateIso,
        'weekOfMonth': weekOfMonth,
        'humanPersonId': humanPersonId,
        'locationEntityId': locationEntityId,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory RoutineProposal.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('invalid_routine_proposal_v1');
    }
    final map = Map<String, Object?>.fromEntries(
      value.entries.map((entry) {
        if (entry.key is! String) {
          throw const FormatException('invalid_routine_proposal_v1');
        }
        return MapEntry(entry.key as String, entry.value);
      }),
    );
    T enumValue<T extends Enum>(List<T> values, String key) {
      final raw = map[key];
      if (raw is! String) {
        throw const FormatException('invalid_routine_proposal_v1');
      }
      return values.where((item) => item.name == raw).firstOrNull ??
          (throw const FormatException('invalid_routine_proposal_v1'));
    }

    final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(map['expiresAt']?.toString() ?? '');
    if (createdAt == null ||
        updatedAt == null ||
        expiresAt == null ||
        map['days'] is! List) {
      throw const FormatException('invalid_routine_proposal_v1');
    }
    return RoutineProposal(
      proposalId: map['proposalId']?.toString() ?? '',
      logicalRequestId: map['logicalRequestId']?.toString() ?? '',
      accountScopeId: map['accountScopeId']?.toString() ?? '',
      state: enumValue(RoutineProposalState.values, 'state'),
      title: map['title'] as String?,
      recurrenceType: map['recurrenceType'] == null
          ? null
          : enumValue(RoutineRecurrenceType.values, 'recurrenceType'),
      days: (map['days'] as List).whereType<int>().toList(),
      startTime: map['startTime'] as String?,
      durationMinutes: map['durationMinutes'] as int?,
      anchorDateIso: map['anchorDateIso'] as String?,
      weekOfMonth: map['weekOfMonth'] as int?,
      humanPersonId: map['humanPersonId'] as String?,
      locationEntityId: map['locationEntityId'] as String?,
      travelGoMinutes: map['travelGoMinutes'] as int? ?? 0,
      travelBackMinutes: map['travelBackMinutes'] as int? ?? 0,
      marginMinutes: map['marginMinutes'] as int? ?? 0,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      schemaVersion: map['schemaVersion'] as int? ?? 0,
    );
  }
}

final class RoutineModel {
  static const currentSchemaVersion = 1;

  RoutineModel({
    required this.id,
    required this.accountScopeId,
    required this.logicalRequestId,
    required this.title,
    required this.recurrenceType,
    required List<int> days,
    required this.startTime,
    required this.durationMinutes,
    required this.travelGoMinutes,
    required this.travelBackMinutes,
    required this.marginMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.anchorDateIso,
    this.weekOfMonth,
    this.humanPersonId,
    this.locationEntityId,
    this.status = RoutineStatus.active,
    this.schemaVersion = currentSchemaVersion,
  }) : days = List.unmodifiable(List<int>.of(days)..sort()) {
    if (id.trim().isEmpty ||
        accountScopeId.trim().isEmpty ||
        logicalRequestId.trim().isEmpty ||
        title.trim().isEmpty ||
        this.days.any((day) => day < 1 || day > 7) ||
        !_validTime(startTime) ||
        durationMinutes < 1 ||
        travelGoMinutes < 0 ||
        travelBackMinutes < 0 ||
        marginMinutes < 0 ||
        !createdAt.isUtc ||
        !updatedAt.isUtc ||
        updatedAt.isBefore(createdAt) ||
        schemaVersion != currentSchemaVersion ||
        !_validRecurrence()) {
      throw const FormatException('invalid_routine_v1');
    }
  }

  final String id;
  final String accountScopeId;
  final String logicalRequestId;
  final String title;
  final String? humanPersonId;
  final RoutineRecurrenceType recurrenceType;
  final List<int> days;
  final String startTime;
  final int durationMinutes;
  final String? anchorDateIso;
  final int? weekOfMonth;
  final int travelGoMinutes;
  final int travelBackMinutes;
  final int marginMinutes;
  final String? locationEntityId;
  final RoutineStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  String get endTime {
    final parts = startTime.split(':');
    final start =
        DateTime.utc(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
    final end = start.add(Duration(minutes: durationMinutes));
    return '${end.hour.toString().padLeft(2, '0')}:'
        '${end.minute.toString().padLeft(2, '0')}';
  }

  bool _validRecurrence() => switch (recurrenceType) {
        RoutineRecurrenceType.weekdays => days.isEmpty,
        RoutineRecurrenceType.weekly => days.isNotEmpty,
        RoutineRecurrenceType.biweekly =>
          days.isNotEmpty && _validDateIso(anchorDateIso ?? ''),
        RoutineRecurrenceType.monthlyNthWeekday => days.length == 1 &&
            (weekOfMonth == -1 ||
                (weekOfMonth != null &&
                    weekOfMonth! >= 1 &&
                    weekOfMonth! <= 5)),
      };

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'proposalId': id,
        'accountScopeId': accountScopeId,
        'logicalRequestId': logicalRequestId,
        'title': title,
        'humanPersonId': humanPersonId,
        'recurrenceType': recurrenceType.name,
        'days': days,
        'startTime': startTime,
        'durationMinutes': durationMinutes,
        'anchorDateIso': anchorDateIso,
        'weekOfMonth': weekOfMonth,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        'locationEntityId': locationEntityId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, Object?> canonicalPayload() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'proposalId': id,
        'accountScopeId': accountScopeId,
        'logicalRequestId': logicalRequestId,
        'title': title,
        'humanPersonId': humanPersonId,
        'recurrenceType': recurrenceType.name,
        'days': days,
        'startTime': startTime,
        'durationMinutes': durationMinutes,
        'anchorDateIso': anchorDateIso,
        'weekOfMonth': weekOfMonth,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        'locationEntityId': locationEntityId,
        'status': status.name,
      };

  bool hasSameCanonicalPayload(RoutineModel other) {
    final left = canonicalPayload();
    final right = other.canonicalPayload();
    return left.keys.every(
          (key) => key == 'days' || left[key] == right[key],
        ) &&
        _sameDays(other.days);
  }

  bool _sameDays(List<int> other) =>
      days.length == other.length &&
      days.indexed.every((entry) => entry.$2 == other[entry.$1]);

  factory RoutineModel.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String key) =>
        values.where((value) => value.name == json[key]).firstOrNull ??
        (throw const FormatException('invalid_routine_v1'));
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    if (createdAt == null ||
        updatedAt == null ||
        json['days'] is! List ||
        json['proposalId']?.toString() != json['id']?.toString()) {
      throw const FormatException('invalid_routine_v1');
    }
    return RoutineModel(
      id: json['id']?.toString() ?? '',
      accountScopeId: json['accountScopeId']?.toString() ?? '',
      logicalRequestId: json['logicalRequestId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      humanPersonId: json['humanPersonId'] as String?,
      recurrenceType: enumValue(RoutineRecurrenceType.values, 'recurrenceType'),
      days: (json['days'] as List).whereType<int>().toList(),
      startTime: json['startTime']?.toString() ?? '',
      durationMinutes:
          json['durationMinutes'] is int ? json['durationMinutes'] as int : 0,
      anchorDateIso: json['anchorDateIso'] as String?,
      weekOfMonth: json['weekOfMonth'] as int?,
      travelGoMinutes:
          json['travelGoMinutes'] is int ? json['travelGoMinutes'] as int : 0,
      travelBackMinutes: json['travelBackMinutes'] is int
          ? json['travelBackMinutes'] as int
          : 0,
      marginMinutes:
          json['marginMinutes'] is int ? json['marginMinutes'] as int : 0,
      locationEntityId: json['locationEntityId'] as String?,
      status: enumValue(RoutineStatus.values, 'status'),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      schemaVersion:
          json['schemaVersion'] is int ? json['schemaVersion'] as int : 0,
    );
  }

  Map<String, dynamic> toBlockedPeriod() => {
        'type': 'blocked_period',
        'recurrenceType': switch (recurrenceType) {
          RoutineRecurrenceType.weekly => 'weekly',
          RoutineRecurrenceType.weekdays => 'weekdays',
          RoutineRecurrenceType.biweekly => 'biweekly',
          RoutineRecurrenceType.monthlyNthWeekday => 'monthly_nth_weekday',
        },
        'days': days,
        'start': startTime,
        'end': endTime,
        'travelGoMinutes': travelGoMinutes,
        'travelBackMinutes': travelBackMinutes,
        'marginMinutes': marginMinutes,
        if (anchorDateIso != null) 'anchorDateIso': anchorDateIso,
        if (weekOfMonth != null) 'weekOfMonth': weekOfMonth,
      };

  static bool _validTime(String value) =>
      RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  static bool _validDateIso(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }
}
