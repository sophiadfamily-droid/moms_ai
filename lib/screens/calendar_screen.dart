import 'package:flutter/material.dart';

import '../models/agenda_conflict_help.dart';
import '../models/event_model.dart';
import '../models/event_sync_conflict.dart';
import '../models/event_sync_models.dart';
import '../models/routine/routine_agenda_item.dart';
import '../services/event_service.dart';
import '../services/event_mutation_result.dart';
import '../services/event_mutation_service.dart';
import '../services/routine/routine_agenda_service.dart';
import '../services/routine_repository.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.loadEventsForTest,
    this.addEventForTest,
    this.mutateEventForTest,
    this.deleteEventForTest,
    this.loadSyncConflictsForTest,
    this.resolveSyncConflictForTest,
    this.eventsVersionForTest,
    this.loadRoutinesForDayForTest,
    this.routinesVersionForTest,
    this.accountScopeToken = 'guest',
    this.initialDate,
    this.highlightedEventId,
    this.highlightedRoutineId,
    this.highlightedEventTitle,
    this.highlightedRoutineTitle,
    this.onAskZeliaForConflict,
  });

  final Future<List<EventModel>> Function()? loadEventsForTest;
  final Future<void> Function(EventModel event)? addEventForTest;
  final Future<EventMutationResult> Function({
    required EventModel existing,
    required EventModel proposed,
    required int expectedEventRevision,
    required EventParticipantMutationIntent participantIntent,
  })? mutateEventForTest;
  final Future<EventMutationResult> Function({
    required EventModel existing,
    required int expectedEventRevision,
  })? deleteEventForTest;
  final ValueNotifier<int>? eventsVersionForTest;
  final Future<List<RoutineAgendaItem>> Function(
    String accountScopeId,
    DateTime day,
  )? loadRoutinesForDayForTest;
  final ValueNotifier<int>? routinesVersionForTest;
  final String accountScopeToken;
  final DateTime? initialDate;
  final String? highlightedEventId;
  final String? highlightedRoutineId;
  final String? highlightedEventTitle;
  final String? highlightedRoutineTitle;
  final ValueChanged<AgendaConflictHelp>? onAskZeliaForConflict;
  final Future<List<EventSyncConflict>> Function()? loadSyncConflictsForTest;
  final Future<EventConflictResolutionResult> Function({
    required String conflictId,
    required EventConflictResolutionDecision decision,
    required bool confirmed,
  })? resolveSyncConflictForTest;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<EventModel> events = [];
  List<EventSyncConflict> syncConflicts = [];
  List<RoutineAgendaItem> routineItems = [];

  late DateTime selectedDate;
  late DateTime visibleMonth;

  String selectedView = 'Mois';
  bool loading = true;
  int _loadGeneration = 0;
  int _routineLoadGeneration = 0;
  int _screenInstanceGeneration = 0;

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color textDark = const Color(0xFF1F1A18);
  final Color textSoft = const Color(0xFF8B6F67);

  ValueNotifier<int> get eventsVersion =>
      widget.eventsVersionForTest ?? EventService.eventsVersion;
  ValueNotifier<int> get routineChanges =>
      widget.routinesVersionForTest ?? routinesVersion;

  Future<List<EventModel>> getEvents() {
    return widget.loadEventsForTest?.call() ?? EventService.getEvents();
  }

  Future<List<RoutineAgendaItem>> getRoutinesForDay(DateTime day) =>
      widget.loadRoutinesForDayForTest?.call(widget.accountScopeToken, day) ??
      RoutineAgendaService.production().forDay(
        accountScopeId: widget.accountScopeToken,
        day: day,
      );

  Future<void> addEvent(EventModel event) {
    return widget.addEventForTest?.call(event) ?? EventService.addEvent(event);
  }

  Future<EventMutationResult> mutateEvent({
    required EventModel existing,
    required EventModel proposed,
  }) {
    return widget.mutateEventForTest?.call(
          existing: existing,
          proposed: proposed,
          expectedEventRevision: existing.eventRevision,
          participantIntent: const PreserveEventParticipant(),
        ) ??
        EventService.mutateEvent(
          existing: existing,
          proposed: proposed,
          expectedEventRevision: existing.eventRevision,
        );
  }

  Future<EventMutationResult> deleteEvent(EventModel event) {
    return widget.deleteEventForTest?.call(
          existing: event,
          expectedEventRevision: event.eventRevision,
        ) ??
        EventService.deleteEvent(
          existing: event,
          expectedEventRevision: event.eventRevision,
        );
  }

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate?.toLocal() ?? DateTime.now();
    visibleMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    _screenInstanceGeneration++;
    EventService.updateScreenInstanceGeneration(_screenInstanceGeneration);
    eventsVersion.addListener(loadEvents);
    routineChanges.addListener(loadRoutineItems);
    loadEvents();
    loadRoutineItems();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountScopeToken == widget.accountScopeToken) return;
    _screenInstanceGeneration++;
    _loadGeneration++;
    _routineLoadGeneration++;
    EventService.updateScreenInstanceGeneration(_screenInstanceGeneration);
    setState(() {
      events = [];
      syncConflicts = [];
      routineItems = [];
      loading = true;
    });
    loadEvents();
    loadRoutineItems();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _routineLoadGeneration++;
    eventsVersion.removeListener(loadEvents);
    routineChanges.removeListener(loadRoutineItems);
    super.dispose();
  }

  Future<void> loadEvents() async {
    final generation = ++_loadGeneration;
    final loaded = List<EventModel>.from(await getEvents());
    List<EventSyncConflict> conflicts;
    try {
      conflicts = await (widget.loadSyncConflictsForTest?.call() ??
          EventService.getSyncConflicts());
    } catch (_) {
      // Calendar remains usable before Firebase initialization and in tests.
      conflicts = const [];
    }

    loaded.sort((a, b) {
      final aValue = a.startDateTimeIso.isEmpty
          ? '${a.date}T${a.time}:00'
          : a.startDateTimeIso;
      final bValue = b.startDateTimeIso.isEmpty
          ? '${b.date}T${b.time}:00'
          : b.startDateTimeIso;
      return aValue.compareTo(bValue);
    });

    if (!mounted || generation != _loadGeneration) return;

    setState(() {
      events = loaded;
      syncConflicts = conflicts;
      loading = false;
    });
  }

  Future<void> loadRoutineItems() async {
    final generation = ++_routineLoadGeneration;
    final day = selectedDate;
    List<RoutineAgendaItem> loaded;
    try {
      loaded = await getRoutinesForDay(day);
    } catch (_) {
      loaded = const [];
    }
    if (!mounted ||
        generation != _routineLoadGeneration ||
        formatIsoDate(day) != formatIsoDate(selectedDate)) {
      return;
    }
    setState(() => routineItems = loaded);
  }

  void selectDate(DateTime date) {
    setState(() {
      selectedDate = date;
      routineItems = [];
    });
    loadRoutineItems();
  }

  Future<void> showNextSyncConflict() async {
    if (syncConflicts.isEmpty) return;
    final conflict = syncConflicts.first;
    final decision = await showDialog<EventConflictResolutionDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modification à vérifier'),
        content: const Text(
          'Cet événement a changé ailleurs. Choisissez comment continuer.',
        ),
        actions: conflict.decisions
            .map(
              (item) => TextButton(
                onPressed: () => Navigator.pop(context, item),
                child: Text(_decisionLabel(item)),
              ),
            )
            .toList(),
      ),
    );
    if (decision == null || !mounted) return;
    final requiresConfirmation =
        decision == EventConflictResolutionDecision.retryAgainstLatest ||
            decision == EventConflictResolutionDecision.recreateAsNew ||
            decision == EventConflictResolutionDecision.retryDeletion;
    var confirmed = !requiresConfirmation;
    if (requiresConfirmation) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirmer cette action ?'),
              content: const Text(
                'Zélia relira la dernière version avant toute écriture.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirmer'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed) return;
    final result = await (widget.resolveSyncConflictForTest?.call(
          conflictId: conflict.conflictId,
          decision: decision,
          confirmed: confirmed,
        ) ??
        EventService.resolveSyncConflict(
          conflictId: conflict.conflictId,
          decision: decision,
          confirmed: confirmed,
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          switch (result.status) {
            EventConflictResolutionStatus.success => 'Le conflit a été traité.',
            EventConflictResolutionStatus.planningConflict =>
              'Ce changement crée un conflit dans ton planning. '
                  'Vérifie le créneau avant de réessayer.',
            EventConflictResolutionStatus.cloudChangedAgain =>
              'Cet événement a encore été modifié ailleurs. Recharge-le avant de continuer.',
            EventConflictResolutionStatus.unsupportedRebase =>
              'Cette ancienne modification ne peut pas être reprise automatiquement.',
            _ => 'Le conflit n’a pas pu être traité. Recharge puis réessaie.',
          },
        ),
      ),
    );
    await loadEvents();
  }

  String _decisionLabel(EventConflictResolutionDecision decision) =>
      switch (decision) {
        EventConflictResolutionDecision.keepCloud => 'Garder la version cloud',
        EventConflictResolutionDecision.discardLocal => 'Abandonner localement',
        EventConflictResolutionDecision.retryAgainstLatest => 'Reprendre',
        EventConflictResolutionDecision.recreateAsNew => 'Recréer',
        EventConflictResolutionDecision.cancelDeletion =>
          'Annuler la suppression',
        EventConflictResolutionDecision.retryDeletion =>
          'Retenter la suppression',
      };

  String formatIsoDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String normalizeTime(String value) {
    final clean = value.trim().toLowerCase().replaceAll('h', ':');
    if (clean.isEmpty) return '';
    if (!clean.contains(':')) return '${clean.padLeft(2, '0')}:00';
    final parts = clean.split(':');
    final hour = parts.isNotEmpty ? parts[0].padLeft(2, '0') : '00';
    final minute = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    return '$hour:$minute';
  }

  String buildStartDateTimeIso({required String date, required String time}) {
    final cleanDate = date.trim();
    final cleanTime = normalizeTime(time);
    if (cleanDate.isEmpty || cleanTime.isEmpty) return '';
    return '${cleanDate}T$cleanTime:00';
  }

  String buildEndDateTimeIso({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final startIso = buildStartDateTimeIso(date: date, time: time);
    if (startIso.isEmpty || durationMinutes <= 0) return '';
    final start = DateTime.tryParse(startIso);
    if (start == null) return '';
    final end = start.add(Duration(minutes: durationMinutes));
    final endDate = formatIsoDate(end);
    final endTime =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '${endDate}T$endTime:00';
  }

  String endTimeFromDuration({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final endIso = buildEndDateTimeIso(
        date: date, time: time, durationMinutes: durationMinutes);
    if (endIso.isEmpty) return '';
    return endIso.substring(11, 16);
  }

  String durationLabel(int minutes) {
    if (minutes <= 0) return 'Durée';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '${hours}h';
    return '${hours}h${rest.toString().padLeft(2, '0')}';
  }

  String travelLabel(int minutes) {
    if (minutes <= 0) return 'Aucun';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '${hours}h';
    return '${hours}h${rest.toString().padLeft(2, '0')}';
  }

  String cleanEventTitle(String title) {
    var clean = title.trim();

    if (clean.toLowerCase().startsWith('rendez-vous ')) {
      clean = clean.substring('rendez-vous '.length).trim();
    }

    if (clean.toLowerCase().startsWith('rendez vous ')) {
      clean = clean.substring('rendez vous '.length).trim();
    }

    if (clean.isEmpty) return title.trim();

    return clean[0].toUpperCase() + clean.substring(1);
  }

  bool isTechnicalPlanningNote(String note) {
    final lower = note.toLowerCase();

    return lower.contains('planifié par zelia') ||
        lower.contains('planifie par zelia') ||
        lower.contains('durée du rendez-vous') ||
        lower.contains('duree du rendez-vous') ||
        lower.contains('trajet aller estimé') ||
        lower.contains('trajet aller estime');
  }

  String monthName(int month) {
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return months[month - 1];
  }

  String shortMonthName(int month) {
    const months = [
      'Jan.',
      'Fév.',
      'Mars',
      'Avr.',
      'Mai',
      'Juin',
      'Juil.',
      'Août',
      'Sept.',
      'Oct.',
      'Nov.',
      'Déc.',
    ];
    return months[month - 1];
  }

  String weekdayName(int weekday) {
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return days[weekday - 1];
  }

  String categoryOf(EventModel event) {
    return event.category.trim().isEmpty ? 'Personnel' : event.category;
  }

  Color categoryColor(String category) {
    switch (category) {
      case 'Famille':
        return const Color(0xFFE99D5D);
      case 'Travail':
        return const Color(0xFF6E8FD7);
      case 'Santé':
        return const Color(0xFF65B891);
      default:
        return accent;
    }
  }

  List<DateTime> getMonthDays() {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final startOffset = firstDay.weekday - 1;
    final startDate = firstDay.subtract(Duration(days: startOffset));
    return List.generate(42, (index) => startDate.add(Duration(days: index)));
  }

  DateTime getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime getWeekEnd(DateTime date) {
    return getWeekStart(date).add(const Duration(days: 6));
  }

  bool hasEventOnDay(DateTime day) {
    final date = formatIsoDate(day);
    return events.any((event) => event.date == date);
  }

  List<EventModel> eventsForDay(DateTime day) {
    final date = formatIsoDate(day);
    final filtered = events.where((event) => event.date == date).toList();
    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }

  void previousDay() =>
      selectDate(selectedDate.subtract(const Duration(days: 1)));
  void nextDay() => selectDate(selectedDate.add(const Duration(days: 1)));
  void previousWeek() =>
      selectDate(selectedDate.subtract(const Duration(days: 7)));
  void nextWeek() => selectDate(selectedDate.add(const Duration(days: 7)));
  void previousMonth() => setState(() =>
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1, 1));
  void nextMonth() => setState(() =>
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 1));

  Future<void> showDeleteChoices(EventModel event,
      {bool closeSheetAfterDelete = false}) async {
    final isRecurring = event.parentRecurringId.isNotEmpty;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: textSoft.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Supprimer',
                  style: TextStyle(
                      color: textDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: Icon(Icons.event_busy_outlined, color: accent),
                  title: const Text('Supprimer cet événement uniquement'),
                  onTap: () => Navigator.pop(context, 'one'),
                ),
                if (isRecurring)
                  ListTile(
                    leading: Icon(Icons.repeat_rounded, color: accent),
                    title: const Text('Supprimer toute la série'),
                    onTap: () => Navigator.pop(context, 'series'),
                  ),
                ListTile(
                  leading: Icon(Icons.close, color: textSoft),
                  title: const Text('Annuler'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;

    final targets = choice == 'series' && isRecurring
        ? events
            .where((item) => item.parentRecurringId == event.parentRecurringId)
            .toList(growable: false)
        : [event];
    if (targets.length > 1 && widget.deleteEventForTest == null) {
      final batch = await EventService.deleteEvents(targets);
      if (!batch.isComplete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Cet événement a changé. Rechargez l'agenda puis réessayez.",
              ),
            ),
          );
        }
        return;
      }
    } else {
      for (final target in targets) {
        final result = await deleteEvent(target);
        if (result.status != EventMutationStatus.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Cet événement a changé. Rechargez l'agenda puis réessayez.",
                ),
              ),
            );
          }
          return;
        }
      }
    }

    if (!mounted) return;

    if (closeSheetAfterDelete && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    await loadEvents();
  }

  Widget buildSheetTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(color: textSoft),
          hintText: hint,
        ),
      ),
    );
  }

  Widget buildChoiceChip({
    IconData? icon,
    required String label,
    required bool selected,
    required Color color,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: selected ? color : accent.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: selected ? color : textSoft),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
                color: selected ? color : textDark,
                fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  EventModel? findManualOverlapConflict({
    required EventModel candidate,
    EventModel? ignoredEvent,
  }) {
    for (final existingEvent in events) {
      if (ignoredEvent != null &&
          EventService.areSameEvent(existingEvent, ignoredEvent)) {
        continue;
      }

      if (EventService.eventsProtectedOverlap(existingEvent, candidate)) {
        return existingEvent;
      }
    }

    return null;
  }

  Future<bool> confirmManualOverlap({
    required EventModel conflict,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Créneau déjà occupé"),
          content: Text(
            "Ce rendez-vous chevauche déjà « ${conflict.title} ».\n\n"
            "Tu veux quand même enregistrer cette modification ?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Enregistrer quand même"),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> showEventDialog({EventModel? event}) async {
    final isEdit = event != null;
    DateTime selectedEventDate =
        DateTime.tryParse(event?.date ?? '') ?? selectedDate;
    String selectedEventTime = normalizeTime(event?.time ?? '');
    String selectedCategory = event == null ? 'Personnel' : categoryOf(event);
    int selectedDuration =
        event?.durationMinutes == 0 ? 60 : event?.durationMinutes ?? 60;

    int selectedTravelGoMinutes = event?.resolvedTravelGoMinutes ?? 0;
    int selectedTravelBackMinutes = event?.resolvedTravelBackMinutes ?? 0;
    int selectedMarginMinutes = event?.marginMinutes ?? 0;

    final titleController = TextEditingController(text: event?.title ?? '');
    final notesController = TextEditingController(text: event?.notes ?? '');

    Future<void> pickDate(StateSetter setModalState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: selectedEventDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: accent,
                onPrimary: Colors.white,
                surface: bg,
                onSurface: textDark,
              ),
              dialogTheme: DialogThemeData(backgroundColor: bg),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked == null) return;
      setModalState(() => selectedEventDate = picked);
    }

    Future<void> pickTime(StateSetter setModalState) async {
      final initialParts = selectedEventTime.split(':');
      final initialHour =
          initialParts.isNotEmpty ? int.tryParse(initialParts[0]) ?? 9 : 9;
      final initialMinute =
          initialParts.length > 1 ? int.tryParse(initialParts[1]) ?? 0 : 0;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: accent,
                onPrimary: Colors.white,
                surface: bg,
                onSurface: textDark,
              ),
              dialogTheme: DialogThemeData(backgroundColor: bg),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked == null) return;
      setModalState(() {
        selectedEventTime =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }

    Future<void> pickCustomDuration(StateSetter setModalState) async {
      final hoursController = TextEditingController();
      final minutesController = TextEditingController();
      final picked = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: bg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Text('Durée personnalisée',
                style: TextStyle(color: textDark, fontWeight: FontWeight.w900)),
            content: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: hoursController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Heures',
                        labelStyle: TextStyle(color: textSoft)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: 'Minutes',
                        labelStyle: TextStyle(color: textSoft)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Annuler', style: TextStyle(color: textSoft))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                onPressed: () {
                  final hours = int.tryParse(hoursController.text) ?? 0;
                  final minutes = int.tryParse(minutesController.text) ?? 0;
                  final total = (hours * 60) + minutes;
                  if (total > 0) Navigator.pop(context, total);
                },
                child: const Text('Valider'),
              ),
            ],
          );
        },
      );
      if (picked == null || picked <= 0) return;
      setModalState(() => selectedDuration = picked);
    }

    Future<int?> pickCustomMinutes({
      required String title,
      required int currentValue,
      required String zeroLabel,
    }) async {
      final controller = TextEditingController(
        text: currentValue == 0 ? '' : currentValue.toString(),
      );

      return showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: bg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Text(
              title,
              style: TextStyle(color: textDark, fontWeight: FontWeight.w900),
            ),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Minutes',
                hintText: 'Ex : 20',
                labelStyle: TextStyle(color: textSoft),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: Text(
                  zeroLabel,
                  style: TextStyle(
                    color: textSoft,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  final value = int.tryParse(controller.text.trim()) ?? 0;
                  Navigator.pop(context, value < 0 ? 0 : value);
                },
                child: const Text('Valider'),
              ),
            ],
          );
        },
      );
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final dateLabel =
                '${selectedEventDate.day} ${monthName(selectedEventDate.month)} ${selectedEventDate.year}';

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.90),
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 14))
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                                color: textSoft.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(100))),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18)),
                            child: Icon(
                                isEdit
                                    ? Icons.edit_calendar_outlined
                                    : Icons.add_rounded,
                                color: accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              isEdit
                                  ? "Modifier l'événement"
                                  : 'Nouvel événement',
                              style: TextStyle(
                                  color: textDark,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (isEdit)
                            IconButton(
                              onPressed: () => showDeleteChoices(event,
                                  closeSheetAfterDelete: true),
                              icon: Icon(Icons.delete_outline,
                                  color: accent, size: 28),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      buildSheetTextField(
                          controller: titleController,
                          label: 'Titre',
                          hint: 'Ex : RDV dentiste'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => pickDate(setModalState),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                        color: accent.withValues(alpha: 0.10))),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_month_outlined,
                                        color: accent),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(dateLabel,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: textDark,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => pickTime(setModalState),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                        color: accent.withValues(alpha: 0.10))),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time, color: accent),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        selectedEventTime.isEmpty
                                            ? 'Heure'
                                            : selectedEventTime,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: selectedEventTime.isEmpty
                                                ? textSoft
                                                : textDark,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('Durée',
                          style: TextStyle(
                              color: textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...[15, 30, 60].map((minutes) {
                            final selected = selectedDuration == minutes;
                            return GestureDetector(
                              onTap: () => setModalState(
                                  () => selectedDuration = minutes),
                              child: buildChoiceChip(
                                  icon: Icons.timer_outlined,
                                  label: durationLabel(minutes),
                                  selected: selected,
                                  color: accent),
                            );
                          }),
                          GestureDetector(
                            onTap: () => pickCustomDuration(setModalState),
                            child: buildChoiceChip(
                              icon: Icons.add_rounded,
                              label: selectedDuration != 15 &&
                                      selectedDuration != 30 &&
                                      selectedDuration != 60
                                  ? durationLabel(selectedDuration)
                                  : 'Autre durée',
                              selected: selectedDuration != 15 &&
                                  selectedDuration != 30 &&
                                  selectedDuration != 60,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Trajet aller',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...[0, 10, 20, 30].map((minutes) {
                            final selected = selectedTravelGoMinutes == minutes;
                            return GestureDetector(
                              onTap: () => setModalState(
                                () => selectedTravelGoMinutes = minutes,
                              ),
                              child: buildChoiceChip(
                                icon: minutes == 0
                                    ? Icons.do_not_disturb_alt_outlined
                                    : Icons.directions_car_outlined,
                                label: minutes == 0 ? 'Aucun' : '$minutes min',
                                selected: selected,
                                color: accent,
                              ),
                            );
                          }),
                          GestureDetector(
                            onTap: () async {
                              final picked = await pickCustomMinutes(
                                title: 'Trajet aller',
                                currentValue: selectedTravelGoMinutes,
                                zeroLabel: 'Aucun trajet',
                              );
                              if (picked == null) return;
                              setModalState(
                                () => selectedTravelGoMinutes = picked,
                              );
                            },
                            child: buildChoiceChip(
                              icon: Icons.add_rounded,
                              label: ![0, 10, 20, 30]
                                      .contains(selectedTravelGoMinutes)
                                  ? travelLabel(selectedTravelGoMinutes)
                                  : 'Autre trajet',
                              selected: ![0, 10, 20, 30]
                                  .contains(selectedTravelGoMinutes),
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Trajet retour',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...[0, 10, 20, 30].map((minutes) {
                            final selected =
                                selectedTravelBackMinutes == minutes;
                            return GestureDetector(
                              onTap: () => setModalState(
                                () => selectedTravelBackMinutes = minutes,
                              ),
                              child: buildChoiceChip(
                                icon: minutes == 0
                                    ? Icons.do_not_disturb_alt_outlined
                                    : Icons.directions_car_outlined,
                                label: minutes == 0 ? 'Aucun' : '$minutes min',
                                selected: selected,
                                color: accent,
                              ),
                            );
                          }),
                          GestureDetector(
                            onTap: () async {
                              final picked = await pickCustomMinutes(
                                title: 'Trajet retour',
                                currentValue: selectedTravelBackMinutes,
                                zeroLabel: 'Aucun trajet',
                              );
                              if (picked == null) return;
                              setModalState(
                                () => selectedTravelBackMinutes = picked,
                              );
                            },
                            child: buildChoiceChip(
                              icon: Icons.add_rounded,
                              label: ![0, 10, 20, 30]
                                      .contains(selectedTravelBackMinutes)
                                  ? travelLabel(selectedTravelBackMinutes)
                                  : 'Autre trajet',
                              selected: ![0, 10, 20, 30]
                                  .contains(selectedTravelBackMinutes),
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Marge de sécurité',
                        style: TextStyle(
                          color: textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...[0, 5, 10, 15].map((minutes) {
                            final selected = selectedMarginMinutes == minutes;
                            return GestureDetector(
                              onTap: () => setModalState(
                                () => selectedMarginMinutes = minutes,
                              ),
                              child: buildChoiceChip(
                                icon: minutes == 0
                                    ? Icons.do_not_disturb_alt_outlined
                                    : Icons.shield_outlined,
                                label: minutes == 0 ? 'Aucune' : '$minutes min',
                                selected: selected,
                                color: accent,
                              ),
                            );
                          }),
                          GestureDetector(
                            onTap: () async {
                              final picked = await pickCustomMinutes(
                                title: 'Marge de sécurité',
                                currentValue: selectedMarginMinutes,
                                zeroLabel: 'Aucune marge',
                              );
                              if (picked == null) return;
                              setModalState(
                                () => selectedMarginMinutes = picked,
                              );
                            },
                            child: buildChoiceChip(
                              icon: Icons.add_rounded,
                              label: ![0, 5, 10, 15]
                                      .contains(selectedMarginMinutes)
                                  ? travelLabel(selectedMarginMinutes)
                                  : 'Autre marge',
                              selected: ![0, 5, 10, 15]
                                  .contains(selectedMarginMinutes),
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('Catégorie',
                          style: TextStyle(
                              color: textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['Personnel', 'Famille', 'Travail', 'Santé']
                            .map((category) {
                          final selected = selectedCategory == category;
                          final chipColor = categoryColor(category);
                          return GestureDetector(
                            onTap: () => setModalState(
                                () => selectedCategory = category),
                            child: buildChoiceChip(
                                label: category,
                                selected: selected,
                                color: chipColor),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      buildSheetTextField(
                          controller: notesController,
                          label: 'Notes',
                          hint: 'Détails, adresse, rappel...',
                          maxLines: 3),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Annuler',
                                  style: TextStyle(
                                      color: textSoft,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24))),
                              onPressed: () async {
                                final title = titleController.text.trim();
                                final date = formatIsoDate(selectedEventDate);
                                final time = selectedEventTime;
                                final endTime = endTimeFromDuration(
                                    date: date,
                                    time: time,
                                    durationMinutes: selectedDuration);
                                if (title.isEmpty) return;

                                final totalTravelMinutes =
                                    selectedTravelGoMinutes +
                                        selectedTravelBackMinutes;

                                final updatedEvent = event?.copyWith(
                                      title: title,
                                      date: date,
                                      time: time,
                                      notes: notesController.text.trim(),
                                      category: selectedCategory,
                                      startDateTimeIso: buildStartDateTimeIso(
                                        date: date,
                                        time: time,
                                      ),
                                      endTime: endTime,
                                      endDateTimeIso: buildEndDateTimeIso(
                                        date: date,
                                        time: time,
                                        durationMinutes: selectedDuration,
                                      ),
                                      durationMinutes: selectedDuration,
                                      travelMinutes: totalTravelMinutes,
                                      travelGoMinutes: selectedTravelGoMinutes,
                                      travelBackMinutes:
                                          selectedTravelBackMinutes,
                                      usesSeparateTravelTimes: true,
                                      marginMinutes: selectedMarginMinutes,
                                    ) ??
                                    EventModel(
                                      title: title,
                                      date: date,
                                      time: time,
                                      notes: notesController.text.trim(),
                                      category: selectedCategory,
                                      createdAt: DateTime.now(),
                                      startDateTimeIso: buildStartDateTimeIso(
                                        date: date,
                                        time: time,
                                      ),
                                      endTime: endTime,
                                      endDateTimeIso: buildEndDateTimeIso(
                                        date: date,
                                        time: time,
                                        durationMinutes: selectedDuration,
                                      ),
                                      durationMinutes: selectedDuration,
                                      travelMinutes: totalTravelMinutes,
                                      travelGoMinutes: selectedTravelGoMinutes,
                                      travelBackMinutes:
                                          selectedTravelBackMinutes,
                                      usesSeparateTravelTimes: true,
                                      marginMinutes: selectedMarginMinutes,
                                    );

                                final conflict = findManualOverlapConflict(
                                  candidate: updatedEvent,
                                  ignoredEvent: event,
                                );

                                if (conflict != null) {
                                  final shouldSave = await confirmManualOverlap(
                                    conflict: conflict,
                                  );

                                  if (!shouldSave) return;
                                }

                                if (isEdit) {
                                  final result = await mutateEvent(
                                    existing: event,
                                    proposed: updatedEvent,
                                  );
                                  if (result.status !=
                                          EventMutationStatus.success &&
                                      context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Cet événement a changé. Rechargez l'agenda puis réessayez.",
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                } else {
                                  await addEvent(updatedEvent);
                                }

                                visibleMonth = DateTime(selectedEventDate.year,
                                    selectedEventDate.month, 1);
                                selectDate(selectedEventDate);
                                if (context.mounted) Navigator.pop(context);
                                await loadEvents();
                              },
                              child: Text(isEdit ? 'Enregistrer' : 'Ajouter',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_new, color: textDark, size: 20),
            ),
          ),
          const Spacer(),
          Text('Agenda',
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, color: accent)),
          const Spacer(),
          CircleAvatar(
            radius: 26,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: IconButton(
                onPressed: () => showEventDialog(),
                icon: Icon(Icons.add, color: accent, size: 30)),
          ),
        ],
      ),
    );
  }

  Widget buildSegmentedControl() {
    final items = ['Jour', 'Semaine', 'Mois'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withValues(alpha: 0.12))),
      child: Row(
        children: items.map((item) {
          final selected = selectedView == item;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => selectedView = item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: selected
                        ? Border.all(color: accent.withValues(alpha: 0.5))
                        : null),
                child: Center(
                  child: Text(item,
                      style: TextStyle(
                          color: selected ? accent : textSoft,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildMonthHeader() {
    String title = '${monthName(visibleMonth.month)} ${visibleMonth.year}';
    VoidCallback onPrevious = previousMonth;
    VoidCallback onNext = nextMonth;

    if (selectedView == 'Semaine') {
      final start = getWeekStart(selectedDate);
      final end = getWeekEnd(selectedDate);
      if (start.month == end.month && start.year == end.year) {
        title = '${monthName(start.month)} ${start.year}';
      } else if (start.year == end.year) {
        title =
            '${shortMonthName(start.month)} - ${shortMonthName(end.month)} ${end.year}';
      } else {
        title =
            '${shortMonthName(start.month)} ${start.year} - ${shortMonthName(end.month)} ${end.year}';
      }
      onPrevious = previousWeek;
      onNext = nextWeek;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                  onPressed: onPrevious,
                  icon: Icon(Icons.chevron_left, color: textDark))),
          Expanded(
            child: Center(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: textDark)),
            ),
          ),
          CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                  onPressed: onNext,
                  icon: Icon(Icons.chevron_right, color: textDark))),
        ],
      ),
    );
  }

  Widget buildCalendarGrid() {
    final days = getMonthDays();
    final weekLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: weekLetters.map((letter) {
              return Expanded(
                child: Center(
                    child: Text(letter,
                        style: TextStyle(
                            color: textSoft,
                            fontSize: 17,
                            fontWeight: FontWeight.w700))),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 0.68),
            itemBuilder: (context, index) {
              final day = days[index];
              final isCurrentMonth = day.month == visibleMonth.month;
              final isSelected =
                  formatIsoDate(day) == formatIsoDate(selectedDate);
              final dayEvents = eventsForDay(day).take(3).toList();
              return GestureDetector(
                onTap: () {
                  setState(
                      () => visibleMonth = DateTime(day.year, day.month, 1));
                  selectDate(day);
                },
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? accent : Colors.transparent),
                      child: Center(
                        child: Text(day.day.toString(),
                            style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : isCurrentMonth
                                        ? textDark
                                        : textSoft.withValues(alpha: 0.35),
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 8,
                      child: Center(
                        child: dayEvents.isNotEmpty
                            ? Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: isSelected ? Colors.white : accent,
                                    shape: BoxShape.circle))
                            : const SizedBox(height: 6),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget buildDayHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(28)),
        child: Row(
          children: [
            IconButton(
                onPressed: previousDay,
                icon: Icon(Icons.chevron_left, color: textDark)),
            Expanded(
              child: Column(
                children: [
                  Text(weekdayName(selectedDate.weekday),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: textDark)),
                  const SizedBox(height: 8),
                  Text(
                      '${selectedDate.day} ${monthName(selectedDate.month)} ${selectedDate.year}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18,
                          color: accent,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(
                onPressed: nextDay,
                icon: Icon(Icons.chevron_right, color: textDark)),
          ],
        ),
      ),
    );
  }

  Widget buildWeekHeader() {
    final start = getWeekStart(selectedDate);
    final weekDays =
        List.generate(7, (index) => start.add(Duration(days: index)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        children: weekDays.map((day) {
          final selected = formatIsoDate(day) == formatIsoDate(selectedDate);
          final hasEvent = hasEventOnDay(day);
          return Expanded(
            child: GestureDetector(
              onTap: () => selectDate(day),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color:
                        selected ? accent : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    Text(['L', 'M', 'M', 'J', 'V', 'S', 'D'][day.weekday - 1],
                        style: TextStyle(
                            color: selected ? Colors.white : textSoft,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(day.day.toString(),
                        style: TextStyle(
                            color: selected ? Colors.white : textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    hasEvent
                        ? Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: selected ? Colors.white : accent,
                                shape: BoxShape.circle))
                        : const SizedBox(height: 5),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<EventModel> eventsForSelectedDate() {
    final selectedIsoDate = formatIsoDate(selectedDate);

    final result = events.where((event) {
      return event.date == selectedIsoDate;
    }).toList();

    result.sort((a, b) {
      final aValue = a.startDateTimeIso.isEmpty
          ? '${a.date}T${a.time}:00'
          : a.startDateTimeIso;
      final bValue = b.startDateTimeIso.isEmpty
          ? '${b.date}T${b.time}:00'
          : b.startDateTimeIso;

      return aValue.compareTo(bValue);
    });

    return result;
  }

  List<({EventModel event, RoutineAgendaItem routine})> dailyRoutineConflicts(
    List<EventModel> dayEvents,
  ) {
    final conflicts = <({EventModel event, RoutineAgendaItem routine})>[];
    for (final event in dayEvents) {
      final eventStart = EventService.parseProtectedStart(event);
      final eventEnd = EventService.parseProtectedEnd(event);
      if (eventStart == null || eventEnd == null) continue;
      for (final routine in routineItems) {
        if (eventStart.isBefore(routine.protectedEnd) &&
            routine.protectedStart.isBefore(eventEnd)) {
          conflicts.add((event: event, routine: routine));
        }
      }
    }
    return conflicts;
  }

  Widget buildEventsList() {
    final events = eventsForSelectedDate();
    final routineConflicts = dailyRoutineConflicts(events);
    final focusedEvent = events
        .where((event) => event.id == widget.highlightedEventId)
        .firstOrNull;
    final hasFocusedConflict = routineConflicts.any(
      (conflict) =>
          conflict.event.id == widget.highlightedEventId &&
          conflict.routine.routineId == widget.highlightedRoutineId,
    );
    final focusedRoutineTitle = routineItems
        .where((routine) => routine.routineId == widget.highlightedRoutineId)
        .map((routine) => routine.title)
        .firstOrNull;
    final focusedConflictHelp = focusedEvent != null &&
            widget.highlightedRoutineId?.trim().isNotEmpty == true &&
            !hasFocusedConflict
        ? AgendaConflictHelp(
            eventId: focusedEvent.id ?? '',
            eventTitle: cleanEventTitle(
              widget.highlightedEventTitle ?? focusedEvent.title,
            ),
            routineTitle:
                widget.highlightedRoutineTitle?.trim().isNotEmpty == true
                    ? widget.highlightedRoutineTitle!.trim()
                    : focusedRoutineTitle ?? 'ta routine',
          )
        : null;

    if (events.isEmpty && routineItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Icon(Icons.event_available_outlined, color: accent, size: 30),
              const SizedBox(height: 10),
              Text(
                'Aucun événement prévu',
                style: TextStyle(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Profite de ce moment pour toi.',
                style: TextStyle(color: textSoft, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        children: [
          if (focusedConflictHelp != null)
            buildConflictHelpCard(
              help: focusedConflictHelp,
              keySuffix: widget.highlightedRoutineId!,
              event: focusedEvent!,
            ),
          for (final conflict in routineConflicts)
            buildConflictHelpCard(
              help: AgendaConflictHelp(
                eventId: conflict.event.id ?? '',
                eventTitle: cleanEventTitle(conflict.event.title),
                routineTitle: conflict.routine.title,
              ),
              keySuffix: conflict.routine.routineId,
              event: conflict.event,
            ),
          ...events.map(buildEventCard),
          ...routineItems.map(buildRoutineCard),
        ],
      ),
    );
  }

  Widget buildConflictHelpCard({
    required AgendaConflictHelp help,
    required String keySuffix,
    required EventModel event,
  }) {
    final canAskZelia = widget.onAskZeliaForConflict != null &&
        help.eventId.trim().isNotEmpty &&
        (EventService.parseProtectedEnd(event)?.isAfter(DateTime.now()) ??
            false);
    return Container(
      key: ValueKey('agenda-conflict-${help.eventId}-$keySuffix'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Regarde, « ${help.eventTitle} » et « ${help.routineTitle} » se '
            'chevauchent. Je ne change rien sans ton accord.',
            style: TextStyle(
              color: textDark,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (canAskZelia) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: ValueKey('ask-zelia-${help.eventId}-$keySuffix'),
              onPressed: () => widget.onAskZeliaForConflict!(help),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Aide-moi à trouver une solution'),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildRoutineCard(RoutineAgendaItem routine) {
    final highlighted = routine.routineId == widget.highlightedRoutineId ||
        dailyRoutineConflicts(eventsForSelectedDate())
            .any((conflict) => conflict.routine.routineId == routine.routineId);
    return Container(
      key: ValueKey('routine-agenda-${routine.occurrenceId}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: highlighted ? 0.9 : 0.25),
          width: highlighted ? 2.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.autorenew_rounded, color: accent),
          const SizedBox(width: 14),
          SizedBox(
            width: 92,
            child: Text(
              '${routine.startTime} - ${routine.endTime}',
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routine.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Routine prévue par Zelia',
                  style: TextStyle(color: textSoft, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEventCard(EventModel event) {
    final color = categoryColor(categoryOf(event));
    final displayTitle = cleanEventTitle(event.title);
    final highlighted = event.id == widget.highlightedEventId ||
        dailyRoutineConflicts(eventsForSelectedDate())
            .any((conflict) => conflict.event.id == event.id);

    final details = <String>[
      if (event.durationMinutes > 0)
        'Durée ${durationLabel(event.durationMinutes)}',
      if (event.usesSeparateTravelTimes) ...[
        'Aller ${travelLabel(event.travelGoMinutes)}',
        'Retour ${travelLabel(event.travelBackMinutes)}',
        if (event.marginMinutes > 0)
          'Marge ${travelLabel(event.marginMinutes)}',
      ] else if (event.travelMinutes > 0)
        'Trajet ${travelLabel(event.travelMinutes)}',
      if (event.notes.trim().isNotEmpty &&
          !isTechnicalPlanningNote(event.notes.trim()))
        event.notes.trim(),
    ];

    return GestureDetector(
      onTap: () => showEventDialog(event: event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: highlighted
              ? Border.all(color: accent.withValues(alpha: 0.9), width: 2.5)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 86,
              child: Text(
                event.time.isEmpty
                    ? '--:--'
                    : event.endTime.isEmpty
                        ? event.time
                        : '${event.time} - ${event.endTime}',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        details.join(' • '),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSoft,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    buildTopBar(),
                    if (syncConflicts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ListTile(
                          leading: const Icon(Icons.sync_problem_outlined),
                          title: Text(
                            '${syncConflicts.length} modification(s) à vérifier',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: showNextSyncConflict,
                        ),
                      ),
                    buildSegmentedControl(),
                    if (selectedView == 'Mois') ...[
                      buildMonthHeader(),
                      buildCalendarGrid()
                    ],
                    if (selectedView == 'Semaine') ...[
                      buildMonthHeader(),
                      buildWeekHeader()
                    ],
                    if (selectedView == 'Jour') ...[buildDayHeader()],
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(height: 36),
                    ),
                    buildEventsList(),
                  ],
                ),
              ),
            ),
    );
  }
}
