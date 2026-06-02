import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<EventModel> events = [];

  DateTime selectedDate = DateTime.now();
  DateTime visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  String selectedView = 'Mois';
  bool loading = true;

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color textDark = const Color(0xFF1F1A18);
  final Color textSoft = const Color(0xFF8B6F67);

  @override
  void initState() {
    super.initState();
    EventService.eventsVersion.addListener(loadEvents);
    loadEvents();
  }

  @override
  void dispose() {
    EventService.eventsVersion.removeListener(loadEvents);
    super.dispose();
  }

  Future<void> loadEvents() async {
    final loaded = await EventService.getEvents();

    loaded.sort((a, b) {
      final aValue = a.startDateTimeIso.isEmpty
          ? '${a.date}T${a.time}:00'
          : a.startDateTimeIso;
      final bValue = b.startDateTimeIso.isEmpty
          ? '${b.date}T${b.time}:00'
          : b.startDateTimeIso;
      return aValue.compareTo(bValue);
    });

    if (!mounted) return;

    setState(() {
      events = loaded;
      loading = false;
    });
  }

  String formatIsoDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String normalizeTime(String value) {
    final clean = value.trim().toLowerCase().replaceAll('h', ':');
    if (clean.isEmpty) return '';
    if (!clean.contains(':')) return clean.padLeft(2, '0') + ':00';
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

  void previousDay() => setState(
      () => selectedDate = selectedDate.subtract(const Duration(days: 1)));
  void nextDay() =>
      setState(() => selectedDate = selectedDate.add(const Duration(days: 1)));
  void previousWeek() => setState(
      () => selectedDate = selectedDate.subtract(const Duration(days: 7)));
  void nextWeek() =>
      setState(() => selectedDate = selectedDate.add(const Duration(days: 7)));
  void previousMonth() => setState(() =>
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1, 1));
  void nextMonth() => setState(() =>
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 1));

  bool sameEvent(EventModel first, EventModel second) {
    return first.title == second.title &&
        first.createdAt == second.createdAt &&
        first.date == second.date &&
        first.time == second.time;
  }

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
                color: Colors.black.withOpacity(0.12),
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
                    color: textSoft.withOpacity(0.25),
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

    if (choice == 'series' && isRecurring) {
      events.removeWhere(
          (item) => item.parentRecurringId == event.parentRecurringId);
    } else {
      events.removeWhere((item) => sameEvent(item, event));
    }

    await EventService.updateEvents(events);

    if (closeSheetAfterDelete && context.mounted) {
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
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.10)),
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
        color:
            selected ? color.withOpacity(0.18) : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : accent.withOpacity(0.10)),
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

  Future<void> showEventDialog({EventModel? event}) async {
    final isEdit = event != null;
    DateTime selectedEventDate =
        DateTime.tryParse(event?.date ?? '') ?? selectedDate;
    String selectedEventTime = normalizeTime(event?.time ?? '');
    String selectedCategory = event == null ? 'Personnel' : categoryOf(event);
    int selectedDuration =
        event?.durationMinutes == 0 ? 60 : event?.durationMinutes ?? 60;
    int selectedTravelMinutes = event?.travelMinutes ?? 0;

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
              dialogBackgroundColor: bg,
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
              dialogBackgroundColor: bg,
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

    Future<void> pickCustomTravel(StateSetter setModalState) async {
      final controller = TextEditingController(
          text: selectedTravelMinutes == 0
              ? ''
              : selectedTravelMinutes.toString());
      final picked = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: bg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Text('Temps de trajet',
                style: TextStyle(color: textDark, fontWeight: FontWeight.w900)),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: 'Minutes',
                  hintText: 'Ex : 20',
                  labelStyle: TextStyle(color: textSoft)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: Text('Aucun trajet',
                    style: TextStyle(
                        color: textSoft, fontWeight: FontWeight.w800)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
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
      if (picked == null) return;
      setModalState(() => selectedTravelMinutes = picked);
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
                        color: Colors.black.withOpacity(0.12),
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
                                color: textSoft.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(100))),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: accent.withOpacity(0.12),
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
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                        color: accent.withOpacity(0.10))),
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
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                        color: accent.withOpacity(0.10))),
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
                      Text('Temps de trajet',
                          style: TextStyle(
                              color: textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...[0, 10, 20, 30].map((minutes) {
                            final selected = selectedTravelMinutes == minutes;
                            return GestureDetector(
                              onTap: () => setModalState(
                                  () => selectedTravelMinutes = minutes),
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
                            onTap: () => pickCustomTravel(setModalState),
                            child: buildChoiceChip(
                              icon: Icons.add_rounded,
                              label: selectedTravelMinutes != 0 &&
                                      selectedTravelMinutes != 10 &&
                                      selectedTravelMinutes != 20 &&
                                      selectedTravelMinutes != 30
                                  ? travelLabel(selectedTravelMinutes)
                                  : 'Autre trajet',
                              selected: selectedTravelMinutes != 0 &&
                                  selectedTravelMinutes != 10 &&
                                  selectedTravelMinutes != 20 &&
                                  selectedTravelMinutes != 30,
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

                                final updatedEvent = EventModel(
                                  title: title,
                                  date: date,
                                  time: time,
                                  notes: notesController.text.trim(),
                                  category: selectedCategory,
                                  createdAt: event?.createdAt ?? DateTime.now(),
                                  startDateTimeIso: buildStartDateTimeIso(
                                      date: date, time: time),
                                  endTime: endTime,
                                  endDateTimeIso: buildEndDateTimeIso(
                                      date: date,
                                      time: time,
                                      durationMinutes: selectedDuration),
                                  durationMinutes: selectedDuration,
                                  travelMinutes: selectedTravelMinutes,
                                  isRecurring: event?.isRecurring ?? false,
                                  recurringType: event?.recurringType ?? '',
                                  recurringWeekday:
                                      event?.recurringWeekday ?? 0,
                                  recurringUntil: event?.recurringUntil ?? '',
                                  parentRecurringId:
                                      event?.parentRecurringId ?? '',
                                );

                                if (isEdit) {
                                  final index = events.indexWhere(
                                      (item) => sameEvent(item, event));
                                  if (index != -1) {
                                    events[index] = updatedEvent;
                                    await EventService.updateEvents(events);
                                  }
                                } else {
                                  await EventService.addEvent(updatedEvent);
                                }

                                selectedDate = selectedEventDate;
                                visibleMonth = DateTime(selectedEventDate.year,
                                    selectedEventDate.month, 1);
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
            backgroundColor: accent.withOpacity(0.12),
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
          color: Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: accent.withOpacity(0.12))),
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
                        ? Border.all(color: accent.withOpacity(0.5))
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
                onTap: () => setState(() {
                  selectedDate = day;
                  visibleMonth = DateTime(day.year, day.month, 1);
                }),
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
                                        : textSoft.withOpacity(0.35),
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
            color: Colors.white.withOpacity(0.8),
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
              onTap: () => setState(() => selectedDate = day),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: selected ? accent : Colors.white.withOpacity(0.8),
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

  Widget buildEventCard(EventModel event) {
    final color = categoryColor(categoryOf(event));
    final details = <String>[
      if (event.notes.trim().isNotEmpty) event.notes.trim(),
      if (event.travelMinutes > 0) 'Trajet ${event.travelMinutes} min',
    ];

    return GestureDetector(
      onTap: () => showEventDialog(event: event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(22)),
        child: Row(
          children: [
            Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(10))),
            const SizedBox(width: 18),
            SizedBox(
              width: 70,
              child: Text(
                  event.time.isEmpty
                      ? '--:--'
                      : event.endTime.isEmpty
                          ? event.time
                          : '${event.time} - ${event.endTime}',
                  style: TextStyle(
                      color: color, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w500)),
                  if (details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(details.join(' • '),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textSoft, fontSize: 13)),
                    ),
                ],
              ),
            ),
            IconButton(
                onPressed: () => showDeleteChoices(event),
                icon: Icon(Icons.delete_outline, color: textSoft)),
          ],
        ),
      ),
    );
  }

  Widget buildEventsList() {
    final filtered = eventsForDay(selectedDate);
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Text('Aucun événement 💕',
            style: TextStyle(color: textSoft, fontSize: 16)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
      child: Column(
          children: filtered.map((event) => buildEventCard(event)).toList()),
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
