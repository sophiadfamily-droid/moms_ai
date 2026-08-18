import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/priority/proactive_priority_models.dart';
import '../models/task_model.dart';
import '../services/auth_service.dart';
import '../services/ai_priority_service.dart';
import '../services/app_diagnostics.dart';
import '../services/contextual_support_card_service.dart';
import '../services/mental_load_anticipation_production.dart';
import '../services/mental_load_anticipation_suggestion_service.dart';
import '../services/priority/proactive_interaction_registry.dart';
import '../services/priority/proactive_priority_service.dart';
import '../services/priority/proactive_priority_production.dart';
import '../services/priority/proactive_suggestion_presentation_builder.dart';
import '../services/task_service.dart';
import '../widgets/compact_contextual_support_card.dart';

class TasksScreen extends StatefulWidget {
  final ValueChanged<ProactiveTaskDurationHandoff>? onOpenZeliaSuggestion;
  final ValueChanged<int>? onNavigate;
  final bool isDashboardActive;
  final ProactivePriorityService? proactivePriorityService;
  final MentalLoadAnticipationSuggestionService? mentalLoadSuggestionService;
  final String? highlightedTaskId;
  final ProactiveInteractionRegistry? _proactiveInteractionRegistry;
  ProactiveInteractionRegistry get proactiveInteractionRegistry =>
      _proactiveInteractionRegistry ?? ProactiveInteractionRegistry.instance;

  const TasksScreen({
    super.key,
    this.onOpenZeliaSuggestion,
    this.onNavigate,
    this.isDashboardActive = true,
    this.proactivePriorityService,
    this.mentalLoadSuggestionService,
    this.highlightedTaskId,
    ProactiveInteractionRegistry? proactiveInteractionRegistry,
  }) : _proactiveInteractionRegistry = proactiveInteractionRegistry;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final GlobalKey _highlightedTaskKey = GlobalKey();
  static const bool _priorityDiagnosticsEnabled = bool.fromEnvironment(
    'ZELIA_PRIORITY_DIAGNOSTICS',
  );
  static const String _buildMarker = String.fromEnvironment(
    'ZELIA_BUILD_MARKER',
    defaultValue: 'unset',
  );

  List<TaskModel> tasks = [];

  String selectedFilter = "Toutes";
  bool loading = true;
  bool proactiveLoading = true;
  bool proactiveError = false;
  ProactiveSuggestion? proactiveSuggestion;
  MentalLoadAnticipationSuggestion? mentalLoadSuggestion;
  ProactivePriorityService? _proactiveService;
  MentalLoadAnticipationSuggestionService? _mentalLoadService;
  bool _proactiveEvaluationInFlight = false;
  bool _proactiveReevaluationQueued = false;

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color textDark = const Color(0xFF11181C);
  final Color textSoft = const Color(0xFF8B6F67);

  final List<String> filters = [
    "Toutes",
    "Aujourd’hui",
    "Semaine",
    "Important",
    "Terminé",
  ];

  final List<String> categories = [
    "Perso",
    "Maison",
    "Admin",
    "Famille",
    "Travail",
    "Santé",
  ];

  final List<String> plannings = [
    "Aujourd’hui",
    "Cette semaine",
    "Ce mois-ci",
    "Plus tard",
  ];

  final List<String> priorities = [
    "Basse",
    "Normale",
    "Haute",
  ];

  @override
  void initState() {
    super.initState();
    TaskService.tasksVersion.addListener(loadTasks);
    widget.proactiveInteractionRegistry.addListener(_handleInteractionChange);
    loadTasks();
  }

  @override
  void didUpdateWidget(covariant TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isDashboardActive && widget.isDashboardActive) {
      _loadProactiveSuggestion();
    }
    if (oldWidget.highlightedTaskId != widget.highlightedTaskId) {
      _revealHighlightedTask();
    }
  }

  @override
  void dispose() {
    TaskService.tasksVersion.removeListener(loadTasks);
    widget.proactiveInteractionRegistry
        .removeListener(_handleInteractionChange);
    super.dispose();
  }

  void _handleInteractionChange() {
    if (!mounted || !widget.isDashboardActive) return;
    final scope = widget.proactivePriorityService?.accountScopeId ??
        AuthService.currentUserId;
    if (scope == null ||
        scope.isEmpty ||
        widget.proactiveInteractionRegistry.isActive(scope)) {
      return;
    }
    AppDiagnostics.record(
      component: 'proactive_priority',
      step: 'activation',
      code: AppErrorCode.proactiveNoShow,
      severity: AppErrorSeverity.info,
      metadata: const {'result': 'reevaluation_after_continuation'},
    );
    _loadProactiveSuggestion();
  }

  Future<void> loadTasks() async {
    final loadedTasks = await TaskService.getTasks();
    final sortedTasks = AiPriorityService.sortTasks(loadedTasks);

    if (!mounted) return;

    setState(() {
      tasks = sortedTasks;
      loading = false;
    });
    _revealHighlightedTask();
    await _loadProactiveSuggestion();
  }

  void _revealHighlightedTask() {
    if (widget.highlightedTaskId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _highlightedTaskKey.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    });
  }

  Future<void> _loadProactiveSuggestion() async {
    if (!mounted) return;
    if (_proactiveEvaluationInFlight) {
      _proactiveReevaluationQueued = true;
      return;
    }
    _proactiveEvaluationInFlight = true;
    do {
      _proactiveReevaluationQueued = false;
      await _evaluateProactiveSuggestion();
    } while (
        mounted && widget.isDashboardActive && _proactiveReevaluationQueued);
    _proactiveEvaluationInFlight = false;
  }

  Future<void> _evaluateProactiveSuggestion() async {
    if (!mounted) return;
    if (!widget.isDashboardActive) {
      setState(() {
        proactiveSuggestion = null;
        mentalLoadSuggestion = null;
        proactiveLoading = false;
        proactiveError = false;
      });
      return;
    }
    setState(() {
      proactiveLoading = true;
      proactiveError = false;
    });
    try {
      final scope = widget.proactivePriorityService?.accountScopeId ??
          AuthService.currentUserId;
      if (scope == null || scope.isEmpty) {
        if (!mounted) return;
        setState(() {
          proactiveSuggestion = null;
          mentalLoadSuggestion = null;
          proactiveLoading = false;
        });
        return;
      }
      _proactiveService ??= widget.proactivePriorityService ??
          await ProactivePriorityService.create(
            accountScopeId: scope,
            loadProjection: () =>
                ProactivePriorityProduction.loadProjection(scope),
          );
      final interactionSnapshot =
          widget.proactiveInteractionRegistry.snapshot(scope);
      final decision = await _proactiveService!.evaluate(
        dashboardReady: true,
        interactionActive: interactionSnapshot.isActive,
        registryInstanceIdentifier:
            widget.proactiveInteractionRegistry.diagnosticInstanceIdentifier,
        activeInteractionSources: interactionSnapshot.sources
            .map((source) => source.name)
            .toList(growable: false),
        lastInteractionTransition: interactionSnapshot.lastTransition,
        interactionGeneration: interactionSnapshot.generation,
      );
      final prioritySuggestion =
          decision.suggestion ?? _proactiveService!.currentVisibleSuggestion;
      MentalLoadAnticipationSuggestion? anticipation;
      if (prioritySuggestion == null) {
        try {
          _mentalLoadService ??= widget.mentalLoadSuggestionService ??
              await MentalLoadAnticipationSuggestionService.create(
                accountScopeId: scope,
                loadSuggestions: () =>
                    MentalLoadAnticipationProduction.load(scope),
              );
          anticipation = await _mentalLoadService!.evaluate(
            dashboardReady: true,
            interactionActive: interactionSnapshot.isActive,
          );
        } on Object {
          // Anticipation is an optional, fail-closed fallback. A missing
          // cross-domain proof must never hide the regular task dashboard.
          anticipation = null;
        }
      }
      if (!mounted) return;
      setState(() {
        proactiveSuggestion = prioritySuggestion;
        mentalLoadSuggestion = anticipation;
        proactiveError = false;
        proactiveLoading = false;
      });
      if (decision.suggestion case final suggestion?) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted ||
              proactiveSuggestion?.suggestionId != suggestion.suggestionId) {
            return;
          }
          final confirmed = await _proactiveService!.confirmShown(suggestion);
          if (mounted) {
            setState(() {
              if (!confirmed) {
                final visible = _proactiveService!.currentVisibleSuggestion;
                if (visible?.suggestionId != suggestion.suggestionId ||
                    visible?.materialFingerprint !=
                        suggestion.materialFingerprint) {
                  proactiveSuggestion = null;
                  proactiveError = true;
                }
              }
            });
          }
        });
      } else if (anticipation case final suggestion?) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted ||
              mentalLoadSuggestion?.suggestionId != suggestion.suggestionId) {
            return;
          }
          try {
            final confirmed =
                await _mentalLoadService!.confirmShown(suggestion);
            if (mounted && !confirmed) {
              setState(() => mentalLoadSuggestion = null);
            }
          } on Object {
            if (mounted) setState(() => mentalLoadSuggestion = null);
          }
        });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        proactiveSuggestion = null;
        mentalLoadSuggestion = null;
        proactiveError = false;
        proactiveLoading = false;
      });
    }
  }

  Future<void> _dismissProactiveSuggestion() async {
    final suggestion = proactiveSuggestion;
    final anticipation = mentalLoadSuggestion;
    if (suggestion == null && anticipation == null) return;
    setState(() {
      proactiveSuggestion = null;
      mentalLoadSuggestion = null;
    });
    try {
      if (suggestion != null) {
        await _proactiveService?.dismiss(suggestion);
      } else if (anticipation != null) {
        await _mentalLoadService?.dismiss(anticipation);
      }
    } on Object {
      if (!mounted) return;
      setState(() => proactiveError = true);
    }
  }

  Future<void> _openProactiveSuggestion() async {
    final suggestion = proactiveSuggestion;
    final anticipation = mentalLoadSuggestion;
    if (suggestion == null && anticipation == null) return;
    if (anticipation != null) {
      final matches = tasks.where(
        (task) => task.id == anticipation.anticipation.preparationSourceId,
      );
      if (matches.isNotEmpty && mounted) {
        await _mentalLoadService?.markActedOn(anticipation);
        setState(() => mentalLoadSuggestion = null);
        await showTaskSheet(task: matches.first);
      }
      return;
    }
    final activeSuggestion = suggestion!;
    final sourceTask = _taskForSuggestion(activeSuggestion);
    final presentation = sourceTask == null
        ? null
        : const ProactiveSuggestionPresentationBuilder().build(
            suggestion: activeSuggestion,
            sourceLabel: sourceTask.title,
          );
    await _proactiveService?.markActedOn(activeSuggestion);
    if (activeSuggestion.callToAction ==
            ProactiveSuggestionCallToActionType.completeInformation &&
        presentation != null &&
        sourceTask?.id != null &&
        widget.onOpenZeliaSuggestion != null) {
      widget.onOpenZeliaSuggestion!(
        ProactiveTaskDurationHandoff(
          taskId: sourceTask!.id!,
          logicalRequestId:
              'proactive-duration:${activeSuggestion.suggestionId}:${sourceTask.id}',
          sourceSuggestionId: activeSuggestion.suggestionId,
          sourceEntityReference: activeSuggestion.sourceEntityReferences.first,
          taskTitle: sourceTask.title,
          question: presentation.assistantPrompt,
          createdAt: DateTime.now().toUtc(),
          task: sourceTask,
        ),
      );
      return;
    }
    final sourceId =
        activeSuggestion.sourceEntityReferences.first.split(':').last;
    if (activeSuggestion.callToAction ==
            ProactiveSuggestionCallToActionType.openTask ||
        activeSuggestion.callToAction ==
            ProactiveSuggestionCallToActionType.completeInformation) {
      final matches = tasks.where((task) => task.id == sourceId);
      if (matches.isNotEmpty && mounted) {
        await showTaskSheet(task: matches.first);
      }
      return;
    }
    widget.onNavigate?.call(2);
  }

  TaskModel? _taskForSuggestion(ProactiveSuggestion suggestion) {
    for (final reference in suggestion.sourceEntityReferences) {
      final sourceId = reference.split(':').last;
      final matches = tasks.where((task) => task.id == sourceId);
      if (matches.isNotEmpty) return matches.first;
    }
    return null;
  }

  Future<void> saveCurrentTasks() async {
    final sortedTasks = AiPriorityService.sortTasks(tasks);
    await TaskService.updateTasks(sortedTasks);
    await loadTasks();
  }

  List<TaskModel> get filteredTasks {
    if (selectedFilter == "Aujourd’hui") {
      return tasks.where((task) {
        return !task.isDone && task.planning == "Aujourd’hui";
      }).toList();
    }

    if (selectedFilter == "Semaine") {
      return tasks.where((task) {
        return !task.isDone && task.planning == "Cette semaine";
      }).toList();
    }

    if (selectedFilter == "Important") {
      return tasks.where((task) {
        return !task.isDone && task.isImportant;
      }).toList();
    }

    if (selectedFilter == "Terminé") {
      return tasks.where((task) => task.isDone).toList();
    }

    return tasks;
  }

  List<TaskModel> sectionTasks(String planning) {
    return filteredTasks.where((task) {
      return !task.isDone && task.planning == planning;
    }).toList();
  }

  List<TaskModel> get doneTasks {
    return filteredTasks.where((task) => task.isDone).toList();
  }

  int openCount() {
    return tasks.where((task) => !task.isDone).length;
  }

  int doneCount() {
    return tasks.where((task) => task.isDone).length;
  }

  double progress() {
    if (tasks.isEmpty) return 0;
    return doneCount() / tasks.length;
  }

  int indexOfTask(TaskModel task) {
    return tasks.indexWhere(
      (current) => TaskService.areSameTask(current, task),
    );
  }

  Future<void> toggleTask(TaskModel task) async {
    final index = indexOfTask(task);
    if (index == -1) return;

    tasks[index] = task.copyWith(isDone: !task.isDone);
    tasks = AiPriorityService.sortTasks(tasks);

    await TaskService.updateTasks(tasks);
    await loadTasks();
  }

  Future<void> toggleImportant(TaskModel task) async {
    final index = indexOfTask(task);
    if (index == -1) return;

    tasks[index] = task.copyWith(
      isImportant: !task.isImportant,
      priority: !task.isImportant ? "Haute" : "Normale",
    );

    tasks = AiPriorityService.sortTasks(tasks);

    await TaskService.updateTasks(tasks);
    await loadTasks();
  }

  Future<void> deleteTask(TaskModel task) async {
    tasks.removeWhere((current) => TaskService.areSameTask(current, task));
    await saveCurrentTasks();
  }

  Future<void> clearCompleted() async {
    tasks.removeWhere((task) => task.isDone);
    await saveCurrentTasks();
  }

  String visiblePriorityLabel(TaskModel task) {
    final score = AiPriorityService.calculatePriority(task);

    if (score >= 85) return "Urgent";
    if (score >= 70) return "Important";
    if (task.isImportant) return "Important";
    return "Normal";
  }

  Color visiblePriorityColor(TaskModel task) {
    final label = visiblePriorityLabel(task);

    if (label == "Urgent") return const Color(0xFFE95D5D);
    if (label == "Important") return const Color(0xFFE99D5D);
    return const Color(0xFF65B891);
  }

  String priorityReason(TaskModel task) {
    final title = task.title.toLowerCase();
    final notes = task.notes.toLowerCase();
    final dueDate = task.dueDate.toLowerCase();
    final text = "$title $notes $dueDate";

    if (dueDate.trim().isNotEmpty) {
      return "Échéance à surveiller.";
    }

    if (task.isImportant || task.priority == "Haute") {
      return "Impact important sur ton organisation.";
    }

    if (text.contains("urgent") ||
        text.contains("demain") ||
        text.contains("avant") ||
        text.contains("deadline")) {
      return "À traiter rapidement.";
    }

    if (task.planning == "Aujourd’hui") {
      return "À faire aujourd’hui.";
    }

    if (task.planning == "Plus tard") {
      return "Peut attendre.";
    }

    return "À organiser simplement.";
  }

  Future<void> showTaskSheet({TaskModel? task}) async {
    final isEdit = task != null;

    final titleController = TextEditingController(text: task?.title ?? "");
    final notesController = TextEditingController(text: task?.notes ?? "");
    final dueDateController = TextEditingController(text: task?.dueDate ?? "");

    String category =
        task?.category.isNotEmpty == true ? task!.category : "Perso";

    String planning =
        task?.planning.isNotEmpty == true ? task!.planning : "Aujourd’hui";

    String priority =
        task?.priority.isNotEmpty == true ? task!.priority : "Normale";

    bool important = task?.isImportant ?? false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottom = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                      isEdit ? "Modifier la tâche" : "Nouvelle tâche",
                    ),
                    const SizedBox(height: 18),
                    buildSheetTextField(
                      controller: titleController,
                      label: "Titre",
                      hint: "Ex : Appeler l’école",
                    ),
                    const SizedBox(height: 14),
                    buildSheetTextField(
                      controller: notesController,
                      label: "Notes",
                      hint: "Détails utiles...",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    buildSheetTextField(
                      controller: dueDateController,
                      label: "Date limite",
                      hint: "Ex : vendredi, 12/06, avant fin juin...",
                    ),
                    const SizedBox(height: 18),
                    buildChoiceSection(
                      title: "À faire",
                      items: plannings,
                      selected: planning,
                      onTap: (value) {
                        setModalState(() {
                          planning = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    buildChoiceSection(
                      title: "Priorité",
                      items: priorities,
                      selected: priority,
                      onTap: (value) {
                        setModalState(() {
                          priority = value;
                          important = value == "Haute";
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    buildChoiceSection(
                      title: "Catégorie",
                      items: categories,
                      selected: category,
                      onTap: (value) {
                        setModalState(() {
                          category = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        setModalState(() {
                          important = !important;
                          priority = important ? "Haute" : "Normale";
                        });
                      },
                      child: buildPremiumToggle(
                        icon: important
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        title: "Marquer comme important",
                        active: important,
                      ),
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      isEdit: isEdit,
                      onSave: () async {
                        await HapticFeedback.lightImpact();

                        final title = titleController.text.trim();
                        if (title.isEmpty) return;

                        final updated = task?.copyWith(
                              title: title,
                              category: category,
                              isImportant: important,
                              dueDate: dueDateController.text.trim(),
                              notes: notesController.text.trim(),
                              planning: planning,
                              priority: priority,
                            ) ??
                            TaskModel(
                              title: title,
                              category: category,
                              isDone: false,
                              createdAt: DateTime.now(),
                              isImportant: important,
                              dueDate: dueDateController.text.trim(),
                              notes: notesController.text.trim(),
                              planning: planning,
                              priority: priority,
                            );

                        if (isEdit) {
                          final index = indexOfTask(task);
                          if (index != -1) {
                            tasks[index] = updated;
                            tasks = AiPriorityService.sortTasks(tasks);
                            await TaskService.updateTasks(tasks);
                          }
                        } else {
                          await TaskService.addTask(updated);
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                        }

                        await loadTasks();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildSheetContainer({required Widget child}) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: SingleChildScrollView(child: child),
    );
  }

  Widget buildSheetHandle() {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        decoration: BoxDecoration(
          color: textSoft.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }

  Widget buildSheetTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w900,
        color: textDark,
      ),
    );
  }

  Widget buildSheetActions({
    required bool isEdit,
    required Future<void> Function() onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Annuler",
              style: TextStyle(
                color: textSoft,
                fontWeight: FontWeight.w800,
              ),
            ),
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
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onPressed: onSave,
            child: Text(
              isEdit ? "Enregistrer" : "Ajouter",
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildSheetTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
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
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(color: textSoft),
          hintText: hint,
        ),
      ),
    );
  }

  Widget buildChoiceSection({
    required String title,
    required List<String> items,
    required String selected,
    required Function(String) onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final isSelected = selected == item;

            return GestureDetector(
              onTap: () => onTap(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? accent : accent.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    color: isSelected ? accent : textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget buildPremiumToggle({
    required IconData icon,
    required String title,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active
              ? accent.withValues(alpha: 0.55)
              : accent.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? const Color(0xFFFFB000) : textSoft,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "To-do list",
              style: TextStyle(
                color: textDark,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          CircleAvatar(
            radius: 28,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: IconButton(
              onPressed: () => showTaskSheet(),
              icon: Icon(
                Icons.add,
                color: accent,
                size: 31,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDashboardSummary() {
    final total = tasks.length;
    final open = openCount();
    final done = doneCount();
    final value = progress();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "$open",
                style: TextStyle(
                  color: accent,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? "Rien à faire pour le moment"
                      : "$open tâche(s) à organiser",
                  style: TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "$done terminée(s) • progression ${(value * 100).round()}%",
                  style: TextStyle(
                    color: textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: value.clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: accent.withValues(alpha: 0.10),
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildZeliaSuggestionCard() {
    final suggestion = proactiveSuggestion;
    final anticipation = mentalLoadSuggestion;
    final sourceTask =
        suggestion == null ? null : _taskForSuggestion(suggestion);
    final presentation = suggestion == null || sourceTask == null
        ? null
        : const ProactiveSuggestionPresentationBuilder().build(
            suggestion: suggestion,
            sourceLabel: sourceTask.title,
          );
    final anticipationPresentation = anticipation?.presentation;
    final hasDisplayableSuggestion =
        presentation != null || anticipationPresentation != null;
    final supportMessage = const ContextualSupportCardService().forTasks(
      openCount: tasks.where((task) => !task.isDone).length,
      completedCount: tasks.where((task) => task.isDone).length,
      now: DateTime.now(),
    );
    if (!proactiveLoading &&
        !hasDisplayableSuggestion &&
        !_priorityDiagnosticsEnabled) {
      return CompactContextualSupportCard(
        key: const Key('proactive-priority-card'),
        contentKey: const Key('contextual-support-message'),
        supportMessage: supportMessage,
        accent: accent,
        textColor: textDark,
        secondaryTextColor: textSoft,
      );
    }
    final content = proactiveLoading
        ? Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: LinearProgressIndicator(
                  color: accent.withValues(alpha: 0.35),
                  backgroundColor: Colors.transparent,
                ),
              ),
            ],
          )
        : !hasDisplayableSuggestion
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome, color: accent, size: 23),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      key: const Key('contextual-support-message'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supportMessage.title,
                          style: TextStyle(
                            color: textDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          supportMessage.message,
                          key: Key(supportMessage.semanticKey),
                          style: TextStyle(
                            color: textSoft,
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: accent,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          presentation?.title ??
                              anticipationPresentation!.title,
                          style: TextStyle(
                            color: textDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          presentation?.message ??
                              anticipationPresentation!.message,
                          style: TextStyle(
                            color: textSoft,
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          key: const Key(
                            'proactive-priority-call-to-action',
                          ),
                          onPressed: _openProactiveSuggestion,
                          child: Text(
                            presentation?.callToActionLabel ??
                                anticipationPresentation!.callToActionLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Masquer cette suggestion',
                    onPressed: _dismissProactiveSuggestion,
                    icon: const Icon(Icons.close),
                  ),
                ],
              );
    return Container(
      key: const Key('proactive-priority-card'),
      constraints: const BoxConstraints(minHeight: 112),
      margin: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.90),
            accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          if (_priorityDiagnosticsEnabled) ...[
            const SizedBox(height: 12),
            _buildPriorityDiagnosticPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildPriorityDiagnosticPanel() {
    final snapshot = _proactiveService?.lastEvaluationSnapshot;
    final text = snapshot?.toClosedDiagnosticText() ??
        'buildMarker=$_buildMarker\nsnapshot=unavailable\n'
            'registryInstanceIdentifier='
            '${widget.proactiveInteractionRegistry.diagnosticInstanceIdentifier}';
    return Container(
      key: const Key('proactive-priority-diagnostic-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            style: const TextStyle(fontSize: 10, height: 1.25),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _loadProactiveSuggestion,
                child: const Text('Réévaluer maintenant'),
              ),
              OutlinedButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                child: const Text('Copier le diagnostic'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildFilters() {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedFilter = filter;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.86)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    color: selected ? Colors.white : textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: filters.length,
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 14),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: textDark,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPriorityBadge(TaskModel task) {
    final label = visiblePriorityLabel(task);
    final color = visiblePriorityColor(task);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget buildTaskSection(List<TaskModel> sectionTasks) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(34),
      ),
      child: Column(
        children: sectionTasks.map((task) {
          final index = sectionTasks.indexOf(task);
          final isLast = index == sectionTasks.length - 1;

          return Column(
            children: [
              Dismissible(
                key: ValueKey(
                  task.id ??
                      "${task.title}-${task.createdAt.toIso8601String()}",
                ),
                direction: DismissDirection.horizontal,
                background: buildSwipeBackground(
                  icon: Icons.check_rounded,
                  label: "Terminer",
                  alignLeft: true,
                ),
                secondaryBackground: buildSwipeBackground(
                  icon: Icons.delete_outline,
                  label: "Supprimer",
                  alignLeft: false,
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    await HapticFeedback.lightImpact();
                    await toggleTask(task);
                    return false;
                  }

                  await HapticFeedback.lightImpact();
                  await deleteTask(task);
                  return true;
                },
                child: buildTaskRow(task),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  color: accent.withValues(alpha: 0.08),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget buildSwipeBackground({
    required IconData icon,
    required String label,
    required bool alignLeft,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: EdgeInsets.only(
        left: alignLeft ? 18 : 0,
        right: alignLeft ? 0 : 18,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment:
            alignLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showTaskOptions(TaskModel task) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSheetHandle(),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: accent),
                  title: const Text("Modifier"),
                  onTap: () {
                    Navigator.pop(context);
                    showTaskSheet(task: task);
                  },
                ),
                ListTile(
                  leading: Icon(
                    task.isImportant
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFFFB000),
                  ),
                  title: Text(
                    task.isImportant
                        ? "Retirer des importantes"
                        : "Marquer important",
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await toggleImportant(task);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: accent),
                  title: Text(
                    "Supprimer",
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await deleteTask(task);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildTaskRow(TaskModel task) {
    final highlighted = task.id != null && task.id == widget.highlightedTaskId;
    return AnimatedContainer(
      key: highlighted ? _highlightedTaskKey : null,
      duration: const Duration(milliseconds: 250),
      padding: highlighted ? const EdgeInsets.symmetric(horizontal: 10) : null,
      decoration: highlighted
          ? BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            )
          : null,
      child: GestureDetector(
        onTap: () => toggleTask(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 17),
          child: Row(
            children: [
              buildCheckCircle(
                checked: task.isDone,
                onTap: () => toggleTask(task),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () => showTaskSheet(task: task),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: task.isDone
                              ? textSoft.withValues(alpha: 0.65)
                              : textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          decoration:
                              task.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          buildPriorityBadge(task),
                          buildTag(task.category),
                          if (task.dueDate.trim().isNotEmpty)
                            buildTag(task.dueDate),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        priorityReason(task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (task.notes.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            task.notes,
                            maxLines: 1,
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
              ),
              IconButton(
                onPressed: () => showTaskOptions(task),
                icon: Icon(
                  Icons.more_horiz,
                  color: textSoft,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTag(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: textSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget buildCheckCircle({
    required bool checked,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 27,
        height: 27,
        decoration: BoxDecoration(
          color: checked ? accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: checked ? accent : accent.withValues(alpha: 0.62),
            width: 1.8,
          ),
        ),
        child: checked
            ? const Icon(
                Icons.check,
                color: Colors.white,
                size: 17,
              )
            : null,
      ),
    );
  }

  Widget buildClearCompleted() {
    if (doneTasks.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: clearCompleted,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 16, 24, 34),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: accent.withValues(alpha: 0.10),
              child: Icon(Icons.delete_outline, color: accent),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                "Supprimer les tâches terminées",
                style: TextStyle(
                  color: accent,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: textSoft),
          ],
        ),
      ),
    );
  }

  Widget buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 60, 34, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: accent.withValues(alpha: 0.45),
            size: 54,
          ),
          const SizedBox(height: 16),
          Text(
            "Aucune tâche pour le moment 💕",
            style: TextStyle(
              color: textSoft,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = sectionTasks("Aujourd’hui").isNotEmpty ||
        sectionTasks("Cette semaine").isNotEmpty ||
        sectionTasks("Ce mois-ci").isNotEmpty ||
        sectionTasks("Plus tard").isNotEmpty ||
        doneTasks.isNotEmpty;

    return Scaffold(
      backgroundColor: bg,
      body: loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : SafeArea(
              child: RefreshIndicator(
                color: accent,
                onRefresh: loadTasks,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildHeader(),
                      buildDashboardSummary(),
                      buildZeliaSuggestionCard(),
                      buildFilters(),
                      if (!hasContent) buildEmptyState(),
                      if (sectionTasks("Aujourd’hui").isNotEmpty) ...[
                        buildSectionTitle("Aujourd’hui"),
                        buildTaskSection(sectionTasks("Aujourd’hui")),
                      ],
                      if (sectionTasks("Cette semaine").isNotEmpty) ...[
                        buildSectionTitle("Cette semaine"),
                        buildTaskSection(sectionTasks("Cette semaine")),
                      ],
                      if (sectionTasks("Ce mois-ci").isNotEmpty) ...[
                        buildSectionTitle("Ce mois-ci"),
                        buildTaskSection(sectionTasks("Ce mois-ci")),
                      ],
                      if (sectionTasks("Plus tard").isNotEmpty) ...[
                        buildSectionTitle("Plus tard"),
                        buildTaskSection(sectionTasks("Plus tard")),
                      ],
                      if (doneTasks.isNotEmpty) ...[
                        buildSectionTitle("Terminé"),
                        buildTaskSection(doneTasks),
                      ],
                      buildClearCompleted(),
                      const SizedBox(height: 110),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
