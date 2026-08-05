import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event_model.dart';
import '../models/shopping_item_model.dart';
import '../models/task_model.dart';
import '../models/user_profile.dart';
import '../services/ai_priority_service.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/shopping_service.dart';
import '../services/task_service.dart';
import '../services/notification_service.dart';
import 'daily_summary_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserProfile profile;
  final ValueChanged<int>? onNavigate;
  final ValueChanged<DateTime?>? onOpenAgendaDate;

  const HomeScreen({
    super.key,
    required this.profile,
    this.onNavigate,
    this.onOpenAgendaDate,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController robotController;

  List<EventModel> events = [];
  List<TaskModel> tasks = [];
  List<ShoppingItemModel> shoppingItems = [];
  List<String> familyPhotoPaths = [];

  final ImagePicker imagePicker = ImagePicker();
  final PageController familyPhotoController = PageController();

  static const String familyPhotosKey = "zelia_dashboard_family_photos";

  String get scopedFamilyPhotosKey {
    final scope = AuthService.currentUserId;
    return scope == null || scope.trim().isEmpty
        ? familyPhotosKey
        : '$familyPhotosKey:${scope.trim()}';
  }

  bool loading = true;
  bool hasAttention = false;

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color accentSoft = const Color(0xFFF9DCDC);
  final Color textDark = const Color(0xFF11181C);
  final Color textSoft = const Color(0xFF8B6F67);
  final Color cardWhite = Colors.white;

  @override
  void initState() {
    super.initState();

    robotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    TaskService.tasksVersion.addListener(loadDashboardData);
    ShoppingService.shoppingVersion.addListener(loadDashboardData);
    EventService.eventsVersion.addListener(loadDashboardData);

    loadDashboardData();
  }

  @override
  void dispose() {
    TaskService.tasksVersion.removeListener(loadDashboardData);
    ShoppingService.shoppingVersion.removeListener(loadDashboardData);
    EventService.eventsVersion.removeListener(loadDashboardData);

    robotController.dispose();
    familyPhotoController.dispose();
    super.dispose();
  }

  Future<void> loadDashboardData() async {
    final loadedEvents = await EventService.getEvents();
    final loadedTasks = await TaskService.getTasks();
    final loadedShopping = await ShoppingService.getItems();
    final prefs = await SharedPreferences.getInstance();
    final loadedPhotos = prefs.getStringList(scopedFamilyPhotosKey) ?? [];
    var loadedAttention = false;
    try {
      final summary = await NotificationService.loadDailySummary();
      loadedAttention = summary != null &&
          summary.categoryCounts.values.any((count) => count > 0);
    } on Object {
      // The dashboard remains usable when notification context is unavailable.
    }

    loadedEvents.sort((a, b) {
      final aValue = a.startDateTimeIso.isEmpty
          ? "${a.date}T${a.time}:00"
          : a.startDateTimeIso;
      final bValue = b.startDateTimeIso.isEmpty
          ? "${b.date}T${b.time}:00"
          : b.startDateTimeIso;

      return aValue.compareTo(bValue);
    });

    if (!mounted) {
      return;
    }

    setState(() {
      events = loadedEvents;
      tasks = AiPriorityService.sortTasks(loadedTasks);
      shoppingItems = loadedShopping;
      familyPhotoPaths = loadedPhotos;
      hasAttention = loadedAttention;
      loading = false;
    });
  }

  Future<void> pickFamilyPhotos() async {
    final pickedPhotos = await imagePicker.pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
    );

    if (pickedPhotos.isEmpty) {
      return;
    }

    final paths = pickedPhotos
        .map((photo) => photo.path)
        .where((path) => path.trim().isNotEmpty)
        .toList();

    final updated = [
      ...familyPhotoPaths,
      ...paths,
    ];

    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      scopedFamilyPhotosKey,
      updated,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      familyPhotoPaths = updated;
    });
  }

  Future<void> clearFamilyPhotos() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(scopedFamilyPhotosKey);

    if (!mounted) {
      return;
    }

    setState(() {
      familyPhotoPaths = [];
    });
  }

  String formatIsoDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, "0");
    final d = date.day.toString().padLeft(2, "0");

    return "$y-$m-$d";
  }

  String monthName(int month) {
    const months = [
      "janvier",
      "février",
      "mars",
      "avril",
      "mai",
      "juin",
      "juillet",
      "août",
      "septembre",
      "octobre",
      "novembre",
      "décembre",
    ];

    return months[month - 1];
  }

  String weekdayName(int weekday) {
    const days = [
      "Lundi",
      "Mardi",
      "Mercredi",
      "Jeudi",
      "Vendredi",
      "Samedi",
      "Dimanche",
    ];

    return days[weekday - 1];
  }

  List<EventModel> todayEvents() {
    final today = formatIsoDate(DateTime.now());

    return events.where((event) {
      return event.date == today;
    }).toList();
  }

  List<EventModel> upcomingEvents() {
    final now = DateTime.now();

    final list = events.where((event) {
      final eventDateTime = DateTime.tryParse(event.startDateTimeIso);

      if (eventDateTime == null) {
        return false;
      }

      return !eventDateTime.isBefore(now);
    }).toList();

    list.sort(
      (a, b) => a.startDateTimeIso.compareTo(
        b.startDateTimeIso,
      ),
    );

    return list.take(3).toList();
  }

  int openTasksCount() {
    return tasks.where((task) => !task.isDone).length;
  }

  int importantTasksCount() {
    return tasks.where((task) {
      return !task.isDone &&
          (task.isImportant ||
              task.priority == "Haute" ||
              AiPriorityService.calculatePriority(task) >= 70);
    }).length;
  }

  int shoppingToBuyCount() {
    return shoppingItems.where((item) => !item.isBought).length;
  }

  int importantThingsCount() {
    final count = todayEvents().length +
        importantTasksCount() +
        (shoppingToBuyCount() > 0 ? 1 : 0);

    if (count == 0) {
      return openTasksCount() > 0 ? 1 : 0;
    }

    return count;
  }

  TaskModel? topPriorityTask() {
    final openTasks = tasks.where((task) => !task.isDone).toList();

    if (openTasks.isEmpty) {
      return null;
    }

    final sorted = AiPriorityService.sortTasks(openTasks);

    return sorted.first;
  }

  String topPriorityReason(TaskModel task) {
    final dueDate = task.dueDate.trim().toLowerCase();
    final title = task.title.toLowerCase();
    final notes = task.notes.toLowerCase();
    final text = "$title $notes $dueDate";

    if (dueDate.isNotEmpty) {
      return "Échéance à surveiller";
    }

    if (task.isImportant || task.priority == "Haute") {
      return "Impact important";
    }

    if (task.planning == "Aujourd’hui") {
      return "À faire aujourd’hui";
    }

    if (text.contains("urgent") ||
        text.contains("demain") ||
        text.contains("payer") ||
        text.contains("appeler") ||
        text.contains("banque") ||
        text.contains("edf") ||
        text.contains("facture")) {
      return "À traiter rapidement";
    }

    return "Priorité recommandée";
  }

  String greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return "Bonjour";
    }

    if (hour < 18) {
      return "Bon après-midi";
    }

    return "Bonsoir";
  }

  String firstName() {
    final name = widget.profile.firstName.trim();

    if (name.isEmpty) {
      return "toi";
    }

    return name;
  }

  void navigateToTab(int index) {
    if (widget.onNavigate != null) {
      widget.onNavigate!(index);
    }
  }

  String eventDelayLabel(EventModel event) {
    final eventDateTime = DateTime.tryParse(event.startDateTimeIso);

    if (eventDateTime == null) {
      return "";
    }

    final diff = eventDateTime.difference(DateTime.now());

    if (diff.isNegative) {
      return "";
    }

    if (diff.inMinutes < 60) {
      return "Dans ${diff.inMinutes} min";
    }

    if (diff.inHours < 24) {
      return "Dans ${diff.inHours} h";
    }

    return "";
  }

  Widget buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.22),
              ),
            ),
            child: Center(
              child: Text(
                "Z",
                style: TextStyle(
                  color: accent,
                  fontFamily: "Serif",
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Spacer(),
          buildRoundIcon(
            icon: Icons.notifications_none_rounded,
            hasDot: hasAttention,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DailySummaryScreen(
                    onOpenAgenda: (date) {
                      Navigator.of(context).pop();
                      if (widget.onOpenAgendaDate != null) {
                        widget.onOpenAgendaDate!(date);
                      } else {
                        navigateToTab(2);
                      }
                    },
                    onOpenTasks: () {
                      Navigator.of(context).pop();
                      navigateToTab(3);
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          buildRoundIcon(
            icon: Icons.auto_awesome,
            onTap: () => navigateToTab(1),
          ),
        ],
      ),
    );
  }

  Widget buildRoundIcon({
    required IconData icon,
    required VoidCallback onTap,
    bool hasDot = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: textDark,
              size: 25,
            ),
          ),
          if (hasDot)
            Positioned(
              top: 8,
              right: 9,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildHero() {
    return SizedBox(
      height: 360,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -42,
            top: -10,
            child: AnimatedBuilder(
              animation: robotController,
              builder: (context, child) {
                final breathing = 1 + (robotController.value * 0.018);
                final handsLife = (robotController.value - 0.5) * 8;

                return Transform.translate(
                  offset: Offset(handsLife, 0),
                  child: Transform.scale(
                    scale: breathing,
                    child: child,
                  ),
                );
              },
              child: SizedBox(
                width: 345,
                height: 345,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      right: 22,
                      bottom: 46,
                      child: Container(
                        width: 238,
                        height: 238,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: 0.20),
                              accentSoft.withValues(alpha: 0.24),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Image.asset(
                      "assets/images/zelia_robot_animated.gif",
                      width: 335,
                      height: 335,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          "assets/images/zelia_robot.png",
                          width: 335,
                          height: 335,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 210,
                              height: 210,
                              decoration: BoxDecoration(
                                color: accentSoft.withValues(alpha: 0.78),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.smart_toy_outlined,
                                size: 86,
                                color: accent,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting(),
                  style: TextStyle(
                    color: textDark,
                    fontSize: 31,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  firstName(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 54,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: 238,
                  child: Text(
                    "Je suis là pour t’aider à organiser ta journée ✨",
                    style: TextStyle(
                      color: textDark.withValues(alpha: 0.82),
                      fontSize: 17,
                      height: 1.42,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAssistantCard() {
    final count = importantThingsCount();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.34),
                      accent.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.01),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: accent,
                  size: 34,
                ),
              ),
              const SizedBox(width: 17),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: textDark,
                      fontSize: 24,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    children: [
                      if (count == 0)
                        const TextSpan(
                          text: "Aucune chose importante aujourd’hui.",
                        )
                      else ...[
                        const TextSpan(text: "Tu as "),
                        TextSpan(
                          text: "$count",
                          style: TextStyle(
                            color: accent,
                          ),
                        ),
                        TextSpan(
                          text: count <= 1
                              ? " chose importante aujourd’hui."
                              : " choses importantes aujourd’hui.",
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 91),
              child: Text(
                "Besoin que je t’aide à l’organiser ?",
                style: TextStyle(
                  color: textSoft,
                  height: 1.35,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          buildZeliaButton(
            title: "✨ Communiquer avec Zelia",
            icon: Icons.auto_awesome,
            filled: true,
            onTap: () => navigateToTab(1),
          ),
        ],
      ),
    );
  }

  Widget buildZeliaButton({
    required String title,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.82),
              accent,
            ],
          ),
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.24),
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEventsCard() {
    final list = upcomingEvents();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Prochains événements",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                if (list.isEmpty)
                  Text(
                    "Aucun événement prévu pour le moment.",
                    style: TextStyle(
                      color: textSoft,
                      fontSize: 14,
                    ),
                  )
                else
                  ...list.map(buildEventLine),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                height: 112,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentSoft.withValues(alpha: 0.9),
                      Colors.white.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Image.asset(
                  "assets/images/desk_planner.png",
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          right: -16,
                          bottom: -14,
                          child: Icon(
                            Icons.local_cafe_outlined,
                            color: textSoft.withValues(alpha: 0.18),
                            size: 92,
                          ),
                        ),
                        Icon(
                          Icons.edit_calendar_outlined,
                          color: accent,
                          size: 58,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEventLine(EventModel event) {
    final label = eventDelayLabel(event);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              event.time.isEmpty ? "--:--" : event.time,
              style: TextStyle(
                color: accent,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_2_outlined,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              event.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textDark,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (label.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String weatherEmoji() {
    final hour = DateTime.now().hour;

    if (hour >= 21 || hour < 6) {
      return "🌙";
    }

    return "☀️";
  }

  String smartDaySummary() {
    final eventCount = todayEvents().length;
    final taskCount = openTasksCount();
    final shoppingCount = shoppingToBuyCount();

    if (eventCount == 0 && taskCount == 0 && shoppingCount == 0) {
      return "Journée légère, parfaite pour respirer.";
    }

    if (eventCount >= 3) {
      return "Journée chargée, Zelia peut t’aider à prioriser.";
    }

    if (taskCount >= 5) {
      return "Plusieurs tâches t’attendent, avance étape par étape.";
    }

    if (shoppingCount > 0) {
      return "Quelques courses à prévoir, sans pression.";
    }

    return "Tout est sous contrôle aujourd’hui.";
  }

  String nextPriorityLabel() {
    final topTask = topPriorityTask();

    if (topTask != null) {
      return topTask.title;
    }

    final upcoming = upcomingEvents();

    if (upcoming.isNotEmpty) {
      final event = upcoming.first;
      final time = event.time.isEmpty ? "" : "${event.time} • ";

      return "$time${event.title}";
    }

    if (shoppingToBuyCount() > 0) {
      return "Compléter la liste de courses";
    }

    return "Profiter d’un moment calme";
  }

  String dailyQuote() {
    final quotes = [
      "Un pas après l’autre, tu avances.",
      "Aujourd’hui, tu fais déjà beaucoup.",
      "Doucement, mais sûrement.",
      "Chaque petite victoire compte.",
      "Tu peux avancer sans te presser.",
      "Une chose à la fois.",
      "Tu gères mieux que tu ne crois.",
      "Respire, tu avances.",
      "Le plus important, c’est de commencer.",
      "Ta journée peut rester simple.",
      "Petit pas, grand progrès.",
      "Tu n’as pas besoin de tout faire d’un coup.",
      "Priorise, respire, avance.",
      "Aujourd’hui compte aussi.",
      "Tu construis ton équilibre.",
      "Un moment après l’autre.",
      "Reste douce avec toi-même.",
      "Tu es sur la bonne voie.",
      "Chaque action compte.",
      "Simplement, efficacement.",
    ];

    final index = DateTime.now().day % quotes.length;

    return quotes[index];
  }

  Widget buildTodaySection() {
    final now = DateTime.now();
    final taskTotal = openTasksCount();
    final shoppingTotal = shoppingToBuyCount();
    final doneTasks = tasks.where((task) => task.isDone).length;
    final progress = tasks.isEmpty ? 0.0 : doneTasks / tasks.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Aujourd’hui",
                style: TextStyle(
                  color: Color(0xFF11181C),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 9),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: accent,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Bien organisée",
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            smartDaySummary(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textSoft,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          buildPriorityPill(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              if (width < 520) {
                return Column(
                  children: [
                    buildDateWideCard(now),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: buildTaskMiniCard(
                            count: taskTotal,
                            progress: progress,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildShoppingMiniCard(
                            count: shoppingTotal,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: buildDateMiniCard(now),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: buildTaskMiniCard(
                      count: taskTotal,
                      progress: progress,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: buildShoppingMiniCard(
                      count: shoppingTotal,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dailyQuote(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildPriorityPill() {
    return GestureDetector(
      onTap: () => navigateToTab(3),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: accent.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                nextPriorityLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDateWideCard(DateTime date) {
    final validPhotos = familyPhotoPaths.where((path) {
      return path.trim().isNotEmpty && File(path).existsSync();
    }).toList();

    if (validPhotos.isEmpty) {
      return GestureDetector(
        onTap: pickFamilyPhotos,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.photo_library_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekdayName(date.weekday),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${date.day} ${monthName(date.month)} ${date.year}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textSoft,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Ajouter des photos famille",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    weatherEmoji(),
                    style: const TextStyle(fontSize: 21),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 154,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            PageView.builder(
              controller: familyPhotoController,
              itemCount: validPhotos.length,
              itemBuilder: (context, index) {
                return Image.file(
                  File(validPhotos[index]),
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              },
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weekdayName(date.weekday),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${date.day} ${monthName(date.month)} ${date.year}",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: pickFamilyPhotos,
                    child: buildPhotoActionButton(
                      icon: Icons.add_photo_alternate_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: clearFamilyPhotos,
                    child: buildPhotoActionButton(
                      icon: Icons.close_rounded,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    weatherEmoji(),
                    style: const TextStyle(fontSize: 21),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPhotoActionButton({
    required IconData icon,
  }) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: accent,
        size: 19,
      ),
    );
  }

  Widget buildDateMiniCard(DateTime date) {
    return GestureDetector(
      onTap: () => navigateToTab(2),
      child: Container(
        height: 178,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                color: accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              weekdayName(date.weekday),
              style: TextStyle(
                color: textDark,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              date.day.toString(),
              style: TextStyle(
                color: textDark,
                fontSize: 31,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              "${monthName(date.month)} ${date.year}",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textSoft,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Divider(
              color: accent.withValues(alpha: 0.08),
            ),
            Icon(
              Icons.wb_sunny_outlined,
              color: accent,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              "Belle journée pour avancer.",
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textSoft,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTaskMiniCard({
    required int count,
    required double progress,
  }) {
    return GestureDetector(
      onTap: () => navigateToTab(3),
      child: Container(
        height: 198,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildMiniTopIcon(
              icon: Icons.check_box_outlined,
            ),
            const SizedBox(height: 14),
            Text(
              "To-do list",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$count",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 32,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "tâches\nouvertes",
                    style: TextStyle(
                      color: textSoft,
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 9,
                backgroundColor: accent.withValues(alpha: 0.13),
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildShoppingMiniCard({
    required int count,
  }) {
    return GestureDetector(
      onTap: () => navigateToTab(4),
      child: Container(
        height: 198,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildMiniTopIcon(
              icon: Icons.shopping_bag_outlined,
            ),
            const SizedBox(height: 9),
            Text(
              "Courses",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$count",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 32,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    count <= 1 ? "produit" : "produits",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textSoft,
                      fontSize: 11,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: count == 0 ? 0.08 : (count / 12).clamp(0.12, 1),
                minHeight: 9,
                backgroundColor: accent.withValues(alpha: 0.10),
                color: accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count == 0 ? "Liste vide" : "À acheter aujourd’hui",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMiniTopIcon({
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 49,
          height: 49,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: accent,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.chevron_right,
          color: textDark,
        ),
      ],
    );
  }

  Widget buildProductBubble(IconData icon) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: accentSoft.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: textSoft,
        size: 15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: loading
          ? Center(
              child: CircularProgressIndicator(
                color: accent,
              ),
            )
          : RefreshIndicator(
              color: accent,
              onRefresh: loadDashboardData,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      buildTopBar(),
                      buildHero(),
                      Transform.translate(
                        offset: const Offset(0, -44),
                        child: buildAssistantCard(),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -40),
                        child: buildTodaySection(),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -28),
                        child: buildEventsCard(),
                      ),
                      const SizedBox(height: 88),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
