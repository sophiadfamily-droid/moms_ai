import '../models/event_participant.dart';
import '../models/event_mutation_models.dart';

class ZeliaActionGuardResult {
  final bool isAccepted;
  final Map<String, dynamic>? action;
  final List<String> corrections;
  final String rejectionReason;

  const ZeliaActionGuardResult._({
    required this.isAccepted,
    required this.action,
    required this.corrections,
    required this.rejectionReason,
  });

  factory ZeliaActionGuardResult.accepted({
    required Map<String, dynamic> action,
    List<String> corrections = const [],
  }) {
    return ZeliaActionGuardResult._(
      isAccepted: true,
      action: action,
      corrections: corrections,
      rejectionReason: '',
    );
  }

  factory ZeliaActionGuardResult.rejected(String reason) {
    return ZeliaActionGuardResult._(
      isAccepted: false,
      action: null,
      corrections: const [],
      rejectionReason: reason,
    );
  }
}

class ZeliaActionGuardService {
  static const int maxDurationMinutes = 24 * 60;
  static const int maxTravelMinutes = 8 * 60;
  static const int maxMarginMinutes = 4 * 60;

  static const Set<String> supportedTypes = {
    'shopping',
    'task',
    'event',
    'event_mutation',
  };

  static ZeliaActionGuardResult guard(dynamic rawAction) {
    if (rawAction is! Map) {
      return ZeliaActionGuardResult.rejected('invalid_action_object');
    }

    final source = Map<String, dynamic>.from(rawAction);
    final corrections = <String>[];

    final type = _normalizeType(source['type']);
    if (!supportedTypes.contains(type)) {
      return ZeliaActionGuardResult.rejected('unsupported_action_type');
    }

    if (type == 'event_mutation') {
      return _guardEventMutation(source);
    }

    final title = _cleanText(source['title']);
    if (title.isEmpty) {
      return ZeliaActionGuardResult.rejected('empty_action_title');
    }

    final normalized = <String, dynamic>{
      ...source,
      'type': type,
      'title': title,
      'date': _normalizeDate(source['date'], corrections),
      'time': _normalizeTime(source['time'], corrections),
      'durationMinutes': _normalizeBoundedInteger(
        source['durationMinutes'],
        minimum: 0,
        maximum: maxDurationMinutes,
        field: 'durationMinutes',
        corrections: corrections,
      ),
      'travelMinutes': _normalizeBoundedInteger(
        source['travelMinutes'],
        minimum: 0,
        maximum: maxTravelMinutes,
        field: 'travelMinutes',
        corrections: corrections,
      ),
      'travelGoMinutes': _normalizeBoundedInteger(
        source['travelGoMinutes'],
        minimum: 0,
        maximum: maxTravelMinutes,
        field: 'travelGoMinutes',
        corrections: corrections,
      ),
      'travelBackMinutes': _normalizeBoundedInteger(
        source['travelBackMinutes'],
        minimum: 0,
        maximum: maxTravelMinutes,
        field: 'travelBackMinutes',
        corrections: corrections,
      ),
      'marginMinutes': _normalizeBoundedInteger(
        source['marginMinutes'],
        minimum: 0,
        maximum: maxMarginMinutes,
        field: 'marginMinutes',
        corrections: corrections,
      ),
      'recurringWeekday': _normalizeBoundedInteger(
        source['recurringWeekday'],
        minimum: 0,
        maximum: 7,
        field: 'recurringWeekday',
        corrections: corrections,
      ),
      'category': _cleanText(source['category']),
      'notes': _cleanText(source['notes']),
      'dueDate': _normalizeDate(source['dueDate'], corrections),
      'planning': _cleanText(source['planning']),
      'priority': _cleanText(source['priority']),
      'section': _cleanText(source['section']),
      'departureContext': _cleanText(source['departureContext']),
      'arrivalContext': _cleanText(source['arrivalContext']),
      'recurringUntil': _normalizeDate(
        source['recurringUntil'],
        corrections,
      ),
      'needsDuration': source['needsDuration'] == true,
      'isRecurring': source['isRecurring'] == true,
      'isImportant': source['isImportant'] == true,
      'isUrgent': source['isUrgent'] == true,
      'usesSeparateTravelTimes': source['usesSeparateTravelTimes'] == true,
    };
    normalized.remove('participant');

    final participant = _validatedParticipant(
      source['participant'],
      actionType: type,
      corrections: corrections,
    );
    if (participant != null) normalized['participant'] = participant;

    _normalizeRecurringState(normalized, corrections);
    _normalizeTravelState(normalized, corrections);
    _normalizeTypeSpecificFields(normalized, corrections);

    return ZeliaActionGuardResult.accepted(
      action: normalized,
      corrections: corrections,
    );
  }

  static ZeliaActionGuardResult _guardEventMutation(
    Map<String, dynamic> source,
  ) {
    final operation = source['operation'];
    final actionKeys = switch (operation) {
      'update' => const {'type', 'operation', 'target', 'changes'},
      'replace_participant' => const {
          'type',
          'operation',
          'target',
          'participant'
        },
      'remove_participant' => const {'type', 'operation', 'target'},
      _ => const <String>{},
    };
    if (actionKeys.isEmpty ||
        source.length != actionKeys.length ||
        source.keys.any((key) => !actionKeys.contains(key)) ||
        source['target'] is! Map ||
        (operation == 'update' && source['changes'] is! Map)) {
      return ZeliaActionGuardResult.rejected('invalid_event_mutation');
    }
    final targetMap = Map<String, dynamic>.from(source['target'] as Map);
    final changesMap = operation == 'update'
        ? Map<String, dynamic>.from(source['changes'] as Map)
        : <String, dynamic>{};
    const targetKeys = {'title', 'date', 'time', 'category'};
    const changeKeys = {
      'title',
      'date',
      'time',
      'durationMinutes',
      'travelGoMinutes',
      'travelBackMinutes',
      'marginMinutes',
      'notes',
      'category',
    };
    if (targetMap.isEmpty ||
        (operation == 'update' && changesMap.isEmpty) ||
        targetMap.keys.any((key) => !targetKeys.contains(key)) ||
        changesMap.keys.any((key) => !changeKeys.contains(key))) {
      return ZeliaActionGuardResult.rejected('invalid_event_mutation');
    }
    String? optionalText(
      Map<String, dynamic> map,
      String key, {
      bool allowEmpty = false,
    }) {
      if (!map.containsKey(key)) return null;
      if (map[key] is! String) {
        throw const FormatException('invalid_event_mutation_text');
      }
      final value = _cleanText(map[key]);
      if (!allowEmpty && value.isEmpty) {
        throw const FormatException('invalid_event_mutation_text');
      }
      return value;
    }

    int? optionalInteger(String key, int minimum, int maximum) {
      if (!changesMap.containsKey(key)) return null;
      if (changesMap[key] is! int) {
        throw const FormatException('invalid_event_mutation_number');
      }
      final value = changesMap[key] as int;
      if (value < minimum || value > maximum) {
        throw const FormatException('invalid_event_mutation_number');
      }
      return value;
    }

    try {
      final targetDate = optionalText(targetMap, 'date');
      final targetTime = optionalText(targetMap, 'time');
      final changeDate = optionalText(changesMap, 'date');
      final changeTime = optionalText(changesMap, 'time');
      if ((targetDate != null &&
              _normalizeDate(targetDate, []) != targetDate) ||
          (targetTime != null &&
              _normalizeTime(targetTime, []) != targetTime) ||
          (changeDate != null &&
              _normalizeDate(changeDate, []) != changeDate) ||
          (changeTime != null &&
              _normalizeTime(changeTime, []) != changeTime)) {
        throw const FormatException('invalid_event_mutation_temporal');
      }
      final target = EventMutationTarget(
        title: optionalText(targetMap, 'title'),
        date: targetDate,
        time: targetTime,
        category: optionalText(targetMap, 'category'),
      );
      final request = switch (operation) {
        'update' => EventMutationRequest.update(
            target: target,
            changes: EventMutationChanges(
              title: optionalText(changesMap, 'title'),
              date: changeDate,
              time: changeTime,
              durationMinutes: optionalInteger('durationMinutes', 1, 1440),
              travelGoMinutes: optionalInteger('travelGoMinutes', 0, 480),
              travelBackMinutes: optionalInteger('travelBackMinutes', 0, 480),
              marginMinutes: optionalInteger('marginMinutes', 0, 240),
              notes: optionalText(changesMap, 'notes', allowEmpty: true),
              category: optionalText(changesMap, 'category'),
            ),
          ),
        'replace_participant' => EventMutationRequest.replaceParticipant(
            target: target,
            participant: _validatedParticipant(
                  source['participant'],
                  actionType: 'event',
                  corrections: <String>[],
                ) ??
                (throw const FormatException('invalid_event_participant')),
          ),
        'remove_participant' =>
          EventMutationRequest.removeParticipant(target: target),
        _ => throw const FormatException('invalid_event_mutation'),
      };
      return ZeliaActionGuardResult.accepted(
        action: {'type': 'event_mutation', 'eventMutation': request},
      );
    } on FormatException {
      return ZeliaActionGuardResult.rejected('invalid_event_mutation');
    }
  }

  static EventParticipant? _validatedParticipant(
    dynamic rawParticipant, {
    required String actionType,
    required List<String> corrections,
  }) {
    if (rawParticipant == null) return null;
    if (actionType != 'event' || rawParticipant is! Map) {
      corrections.add('invalid_event_participant_removed');
      return null;
    }

    final participant = Map<Object?, Object?>.from(rawParticipant);
    const allowedKeys = {'label', 'entityType', 'evidence'};
    if (participant.keys.any((key) => !allowedKeys.contains(key)) ||
        participant.length != allowedKeys.length ||
        participant['label'] is! String ||
        participant['entityType'] != 'person' ||
        participant['evidence'] != 'explicit_user_input') {
      corrections.add('invalid_event_participant_removed');
      return null;
    }

    try {
      return EventParticipant(
        label: participant['label']! as String,
        entityType: EventParticipantEntityType.person,
        evidence: EventParticipantEvidence.explicitUserInput,
      );
    } on FormatException {
      corrections.add('invalid_event_participant_removed');
      return null;
    }
  }

  static String _normalizeType(dynamic rawValue) {
    final value = _cleanText(rawValue).toLowerCase();

    if (value == 'todo' || value == 'to-do') {
      return 'task';
    }

    return value;
  }

  static String _cleanText(dynamic rawValue) {
    return rawValue?.toString().trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  }

  static String _normalizeDate(
    dynamic rawValue,
    List<String> corrections,
  ) {
    final value = _cleanText(rawValue);
    if (value.isEmpty) return '';

    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);

    if (match == null) {
      corrections.add('invalid_date_cleared');
      return '';
    }

    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');

    if (year == null || month == null || day == null) {
      corrections.add('invalid_date_cleared');
      return '';
    }

    final parsed = DateTime.tryParse(value);
    final isExactDate = parsed != null &&
        parsed.year == year &&
        parsed.month == month &&
        parsed.day == day;

    if (!isExactDate) {
      corrections.add('invalid_date_cleared');
      return '';
    }

    return value;
  }

  static String _normalizeTime(
    dynamic rawValue,
    List<String> corrections,
  ) {
    var value = _cleanText(rawValue).toLowerCase();

    if (value.isEmpty) return '';

    value = value.replaceAll('h', ':');

    if (!value.contains(':')) {
      final hour = int.tryParse(value);

      if (hour == null || hour < 0 || hour > 23) {
        corrections.add('invalid_time_cleared');
        return '';
      }

      return '${hour.toString().padLeft(2, '0')}:00';
    }

    final parts = value.split(':');

    if (parts.length != 2) {
      corrections.add('invalid_time_cleared');
      return '';
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      corrections.add('invalid_time_cleared');
      return '';
    }

    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static int _normalizeBoundedInteger(
    dynamic rawValue, {
    required int minimum,
    required int maximum,
    required String field,
    required List<String> corrections,
  }) {
    final value = int.tryParse(rawValue?.toString() ?? '') ?? 0;

    if (value < minimum || value > maximum) {
      corrections.add('${field}_reset');
      return 0;
    }

    return value;
  }

  static void _normalizeRecurringState(
    Map<String, dynamic> action,
    List<String> corrections,
  ) {
    final isRecurring = action['isRecurring'] == true;
    final weekday = action['recurringWeekday'] as int;

    if (!isRecurring) {
      action['recurringType'] = '';
      action['recurringWeekday'] = 0;
      action['recurringUntil'] = '';
      return;
    }

    if (weekday < 1 || weekday > 7) {
      action['isRecurring'] = false;
      action['recurringType'] = '';
      action['recurringWeekday'] = 0;
      action['recurringUntil'] = '';
      corrections.add('invalid_recurring_state_reset');
      return;
    }

    action['recurringType'] = 'weekly';
  }

  static void _normalizeTravelState(
    Map<String, dynamic> action,
    List<String> corrections,
  ) {
    final go = action['travelGoMinutes'] as int;
    final back = action['travelBackMinutes'] as int;
    final legacy = action['travelMinutes'] as int;
    final explicitlySeparate = action['usesSeparateTravelTimes'] == true;

    final usesSeparate = explicitlySeparate || go > 0 || back > 0;

    action['usesSeparateTravelTimes'] = usesSeparate;

    if (usesSeparate) {
      action['travelMinutes'] = go + back;
      return;
    }

    action['travelGoMinutes'] = 0;
    action['travelBackMinutes'] = 0;

    if (legacy < 0) {
      action['travelMinutes'] = 0;
      corrections.add('invalid_legacy_travel_reset');
    }
  }

  static void _normalizeTypeSpecificFields(
    Map<String, dynamic> action,
    List<String> corrections,
  ) {
    final type = action['type'];

    if (type != 'event') {
      action['date'] = type == 'task' ? action['date'] : '';
      action['time'] = '';
      action['durationMinutes'] = 0;
      action['needsDuration'] = false;
      action['travelMinutes'] = 0;
      action['travelGoMinutes'] = 0;
      action['travelBackMinutes'] = 0;
      action['usesSeparateTravelTimes'] = false;
      action['marginMinutes'] = 0;
      action['departureContext'] = '';
      action['arrivalContext'] = '';
      action['isRecurring'] = false;
      action['recurringType'] = '';
      action['recurringWeekday'] = 0;
      action['recurringUntil'] = '';
    }

    if (type == 'event') {
      final duration = action['durationMinutes'] as int;
      action['needsDuration'] = duration <= 0;

      if ((action['category'] as String).isEmpty) {
        action['category'] = 'Personnel';
      }
    }

    if (type == 'task') {
      if ((action['planning'] as String).isEmpty) {
        action['planning'] = 'Cette semaine';
      }

      if ((action['priority'] as String).isEmpty) {
        action['priority'] = 'Normale';
      }
    }

    if (type == 'shopping' && (action['section'] as String).isEmpty) {
      action['section'] = 'Aujourd’hui';
    }

    if (action['title'] != _cleanText(action['title'])) {
      corrections.add('title_normalized');
    }
  }
}
