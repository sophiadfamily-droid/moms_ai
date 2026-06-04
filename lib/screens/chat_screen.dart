import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import '../models/task_model.dart';

import '../services/event_service.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import '../services/memory_service.dart';
import '../services/memory_pipeline_service.dart';
import '../services/memory_context_builder_service.dart';
import '../services/memory_reasoning_service.dart';
import '../services/smart_planning_service.dart';
import '../services/smart_planning_response_builder.dart';
import '../services/planning_proposal_service.dart';
import '../services/profile_reasoning_service.dart';
import '../services/planner_engine_service.dart';
import '../services/conflict_engine_service.dart';
import '../services/zelia_response_builder.dart';
import '../services/action_handler_service.dart';

class ChatScreen extends StatefulWidget {
  final UserProfile profile;
  final String? initialAssistantMessage;

  const ChatScreen({
    super.key,
    required this.profile,
    this.initialAssistantMessage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  final VoiceService voiceService = VoiceService();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  bool loading = false;
  bool isListening = false;

  Map<String, dynamic>? pendingDateEvent;
  Map<String, dynamic>? pendingTimeEvent;
  Map<String, dynamic>? pendingDurationEvent;
  Map<String, dynamic>? pendingTravelEvent;
  Map<String, dynamic>? pendingConflictResolutionEvent;
  SmartPlanningProposal? pendingSmartPlanningProposal;
  Map<String, dynamic>? pendingSmartPlanningTask;
  Map<String, dynamic>? pendingDurationPlanningTask;
  Map<String, dynamic>? pendingTravelPlanningTask;

  String currentUserMessage = "";
  String currentConversationId = "";

  final List<Map<String, dynamic>> messages = [
    {
      "role": "assistant",
      "text":
          "Coucou 💕 Moi c'est Zelia. Je suis là pour t'aider à organiser ton quotidien ✨",
    },
  ];

  @override
  void initState() {
    super.initState();
    currentConversationId = DateTime.now().millisecondsSinceEpoch.toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showInitialAssistantMessage(widget.initialAssistantMessage);
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialAssistantMessage != widget.initialAssistantMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showInitialAssistantMessage(widget.initialAssistantMessage);
      });
    }
  }

  void showInitialAssistantMessage(String? text) {
    if (text == null || text.trim().isEmpty) return;

    final alreadyExists = messages.any((message) {
      return message["role"] == "assistant" && message["text"] == text;
    });

    if (alreadyExists || !mounted) return;

    setState(() {
      messages.add({
        "role": "assistant",
        "text": text,
      });
    });

    saveMessageInBackground(
      role: "assistant",
      text: text,
    );
  }

  Future<void> saveMessage({
    required String role,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    try {
      final userRef = firestore.collection("users").doc("demo_user");
      final conversationRef =
          userRef.collection("conversations").doc(currentConversationId);

      await conversationRef.collection("messages").add({
        "role": role,
        "text": text,
        "createdAt": Timestamp.now(),
      });

      await conversationRef.set({
        "updatedAt": Timestamp.now(),
        "lastMessage": text,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void saveMessageInBackground({
    required String role,
    required String text,
  }) {
    saveMessage(role: role, text: text);
  }

  void addAssistantMessage(String text) {
    if (!mounted || text.trim().isEmpty) return;

    setState(() {
      messages.add({
        "role": "assistant",
        "text": text,
      });
    });

    saveMessageInBackground(
      role: "assistant",
      text: text,
    );
  }

  String normalizeTime(String value) {
    final lower = value.trim().toLowerCase();

    if (lower.isEmpty) return "";
    if (PlannerEngineService.saysUnknownTime(lower)) return "";

    final clean = lower.replaceAll("h", ":");

    if (!RegExp(r'^\\d{1,2}(:\\d{1,2})?\$').hasMatch(clean)) {
      return "";
    }

    if (!clean.contains(":")) {
      return "${clean.padLeft(2, "0")}:00";
    }

    final parts = clean.split(":");
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? -1 : 0;

    if (hour < 0 || hour > 23) return "";
    if (minute < 0 || minute > 59) return "";

    return "${hour.toString().padLeft(2, "0")}:${minute.toString().padLeft(2, "0")}";
  }

  String buildStartDateTimeIso({
    required String date,
    required String time,
  }) {
    final cleanTime = normalizeTime(time);

    if (date.trim().isEmpty || cleanTime.isEmpty) return "";

    return "${date}T$cleanTime:00";
  }

  String buildEndDateTimeIso({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final startIso = buildStartDateTimeIso(
      date: date,
      time: time,
    );

    if (startIso.isEmpty || durationMinutes <= 0) return "";

    final start = DateTime.tryParse(startIso);
    if (start == null) return "";

    final end = start.add(Duration(minutes: durationMinutes));
    final endDate = end.toIso8601String().substring(0, 10);
    final endTime = end.toIso8601String().substring(11, 16);

    return "${endDate}T$endTime:00";
  }

  String endTimeFromDuration({
    required String date,
    required String time,
    required int durationMinutes,
  }) {
    final endIso = buildEndDateTimeIso(
      date: date,
      time: time,
      durationMinutes: durationMinutes,
    );

    if (endIso.isEmpty) return "";

    return endIso.substring(11, 16);
  }

  bool durationContextIsClear(String text) {
    final lower = text.toLowerCase();

    return lower.contains("pendant") ||
        lower.contains("durée") ||
        lower.contains("duree") ||
        lower.contains("bloque") ||
        lower.contains("bloquer") ||
        lower.contains("pour ") ||
        (lower.contains("de ") && lower.contains(" à "));
  }

  int parseDurationMinutes(String text) {
    final lower = text.toLowerCase().trim();

    final onlyNumberForDuration = RegExp(r"^\s*\d+\s*$").hasMatch(lower);

    final onlyDuration =
        RegExp(r"^\s*\d+\s*(h|h\d+|min|minutes?)\s*$").hasMatch(lower) ||
            RegExp(r"^\s*\d+h\d+\s*$").hasMatch(lower) ||
            onlyNumberForDuration;

    if (!onlyDuration && !durationContextIsClear(lower)) return 0;

    final hourMinuteMatch = RegExp(r"(\d+)\s*h\s*(\d+)").firstMatch(lower);

    if (hourMinuteMatch != null) {
      final hours = int.tryParse(hourMinuteMatch.group(1) ?? "0") ?? 0;
      final minutes = int.tryParse(hourMinuteMatch.group(2) ?? "0") ?? 0;

      return (hours * 60) + minutes;
    }

    final hourMatch = RegExp(r"(\d+)\s*h").firstMatch(lower);

    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? "0") ?? 0;
      return hours * 60;
    }

    final minuteMatch = RegExp(r"(\d+)\s*(min|minutes)").firstMatch(lower);

    if (minuteMatch != null) {
      return int.tryParse(minuteMatch.group(1) ?? "0") ?? 0;
    }

    final onlyNumber = RegExp(r"^\s*(\d+)\s*$").firstMatch(lower);

    if (onlyNumber != null) {
      final value = int.tryParse(onlyNumber.group(1) ?? "0") ?? 0;
      if (value <= 12) return value * 60;
      return value;
    }

    return 0;
  }

  bool looksLikeNewActionRequest(String text) {
    final lower = text.toLowerCase();

    return lower.contains("il faut") ||
        lower.contains("je dois") ||
        lower.contains("j'ai rendez-vous") ||
        lower.contains("rendez-vous") ||
        lower.contains("rdv") ||
        lower.contains("plus de") ||
        lower.contains("j'ai plus") ||
        lower.contains("il me manque") ||
        lower.contains("appelle") ||
        lower.contains("appeler") ||
        lower.contains("acheter") ||
        lower.contains("pense à") ||
        lower.contains("fais-moi penser");
  }

  bool messageLooksRecurringWeekly() {
    final lower = currentUserMessage.toLowerCase();

    return lower.contains("tous les") ||
        lower.contains("toutes les") ||
        lower.contains("chaque ") ||
        lower.contains("par semaine") ||
        lower.contains("hebdomadaire");
  }

  int weekdayFromText() {
    final lower = currentUserMessage.toLowerCase();

    if (lower.contains("lundi")) return 1;
    if (lower.contains("mardi")) return 2;
    if (lower.contains("mercredi")) return 3;
    if (lower.contains("jeudi")) return 4;
    if (lower.contains("vendredi")) return 5;
    if (lower.contains("samedi")) return 6;
    if (lower.contains("dimanche")) return 7;

    return 0;
  }

  String nextDateForWeekday(int weekday) {
    if (weekday <= 0) return "";

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var daysToAdd = weekday - today.weekday;

    if (daysToAdd < 0) daysToAdd += 7;

    final target = today.add(Duration(days: daysToAdd));
    final y = target.year.toString();
    final m = target.month.toString().padLeft(2, "0");
    final d = target.day.toString().padLeft(2, "0");

    return "$y-$m-$d";
  }

  String joinTitles(List<String> titles) {
    final cleanTitles = titles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toList();

    if (cleanTitles.isEmpty) return "";
    if (cleanTitles.length == 1) return cleanTitles.first;

    if (cleanTitles.length == 2) {
      return "${cleanTitles.first} et ${cleanTitles.last}";
    }

    final firstPart = cleanTitles.sublist(0, cleanTitles.length - 1).join(", ");
    return "$firstPart et ${cleanTitles.last}";
  }

  String buildGroupedActionReply({
    required List<String> shoppingTitles,
    required List<String> taskTitles,
    required List<String> eventTitles,
    String? planningTitle,
  }) {
    final lines = <String>[];

    if (shoppingTitles.isNotEmpty) {
      lines.add("J’ai ajouté ${joinTitles(shoppingTitles)} aux courses.");
    }

    if (taskTitles.isNotEmpty) {
      lines.add(
        "J’ai aussi ajouté ${joinTitles(taskTitles)} dans ta to-do list.",
      );
    }

    if (eventTitles.isNotEmpty) {
      lines.add("J’ai préparé ${joinTitles(eventTitles)} dans l’agenda.");
    }

    if (planningTitle != null && planningTitle.trim().isNotEmpty) {
      lines.add("");
      lines.add(
        "Pour « $planningTitle », veux-tu que je te trouve un créneau "
        "dans ton agenda ?",
      );
    }

    if (lines.isEmpty) return "C’est noté 💕";

    return "C’est noté 💕\n\n${lines.join("\n")}";
  }

  bool eventNeedsTravel(Map<String, dynamic> action) {
    final title = action["title"]?.toString().toLowerCase() ?? "";
    final category = action["category"]?.toString().toLowerCase() ?? "";
    final notes = action["notes"]?.toString().toLowerCase() ?? "";
    final value = "$title $category $notes";

    final noTravel = value.contains("maison") ||
        value.contains("chez moi") ||
        value.contains("à domicile") ||
        value.contains("a domicile") ||
        value.contains("visio") ||
        value.contains("en ligne") ||
        value.contains("téléphone") ||
        value.contains("telephone") ||
        value.contains("appel");

    if (noTravel) return false;

    return true;
  }

  Future<bool> tryCompletePendingSmartPlanning(String text) async {
    final proposal = pendingSmartPlanningProposal;

    if (proposal == null) return false;

    if (PlannerEngineService.isNegativeAnswer(text)) {
      pendingSmartPlanningProposal = null;

      const reply =
          "D’accord 💕 Je ne réserve rien dans l’agenda pour le moment.";

      addAssistantMessage(reply);
      return true;
    }

    if (!PlannerEngineService.isPositiveAnswer(text)) {
      const reply =
          "Dis-moi simplement oui pour réserver ce créneau, ou non pour ne rien ajouter à l’agenda 💕";

      addAssistantMessage(reply);
      return true;
    }

    final event = SmartPlanningService.eventFromProposal(proposal);

    final conflictEvent = await EventService.getOverlapConflict(
      candidate: event,
    );

    if (conflictEvent != null) {
      pendingSmartPlanningProposal = null;

      final reply = "Je n’ai pas réservé le créneau, car il y a maintenant "
          "un conflit avec : ${conflictEvent.title}. "
          "Je peux chercher un autre créneau si tu veux.";

      addAssistantMessage(reply);
      return true;
    }

    await EventService.addEvent(event);

    await NotificationService.showNotification(
      title: "Créneau réservé 📅",
      body: proposal.taskTitle,
    );

    pendingSmartPlanningProposal = null;

    final detailLines = <String>[
      "C’est fait 💕 J’ai réservé « ${proposal.taskTitle} » "
          "de ${proposal.startTime} à ${proposal.endTime} dans ton agenda.",
      "",
      "Détail prévu :",
      "• ${SmartPlanningService.durationLabel(proposal.actionMinutes)} pour la to-do",
      if (proposal.travelGoMinutes > 0)
        "• ${SmartPlanningService.durationLabel(proposal.travelGoMinutes)} de trajet aller",
      if (proposal.travelBackMinutes > 0)
        "• ${SmartPlanningService.durationLabel(proposal.travelBackMinutes)} de trajet retour",
      if (proposal.marginMinutes > 0)
        "• ${SmartPlanningService.durationLabel(proposal.marginMinutes)} de marge",
      "",
      "Total réservé : ${SmartPlanningService.durationLabel(proposal.totalMinutes)}.",
    ];

    addAssistantMessage(detailLines.join("\n"));
    return true;
  }

  Future<bool> tryCompletePendingPlanningRequest(String text) async {
    final pending = pendingSmartPlanningTask;

    if (pending == null) return false;

    final task = pending["task"];

    if (task is! TaskModel) {
      pendingSmartPlanningTask = null;
      return false;
    }

    if (PlannerEngineService.isNegativeAnswer(text)) {
      pendingSmartPlanningTask = null;

      final reply = SmartPlanningResponseBuilder.keepOnlyTodo(task.title);

      addAssistantMessage(reply);
      return true;
    }

    if (!PlannerEngineService.isPositiveAnswer(text)) {
      if (looksLikeNewActionRequest(text)) {
        pendingSmartPlanningTask = null;
        return false;
      }

      final reply =
          SmartPlanningResponseBuilder.askPlanningConfirmation(task.title);

      addAssistantMessage(reply);
      return true;
    }

    final originalMessage = pending["originalMessage"]?.toString() ?? "";
    final type = SmartPlanningService.detectTaskType(originalMessage, task);
    final outside = SmartPlanningService.isOutsideTask(
      type: type,
      originalMessage: originalMessage,
      task: task,
    );

    final relatedTasks = outside
        ? await SmartPlanningService.getRelatedOutsideTasks(
            mainTask: task,
            originalMessage: originalMessage,
          )
        : <TaskModel>[task];

    final hasGroupedTasks = relatedTasks.length > 1;

    final estimatedMinutes = hasGroupedTasks
        ? SmartPlanningService.estimateGroupedActionMinutes(relatedTasks)
        : SmartPlanningService.actionDurationForType(
            type,
            originalMessage,
            task,
          );

    pendingSmartPlanningTask = null;

    pendingDurationPlanningTask = {
      "task": task,
      "originalMessage": originalMessage,
      "type": type,
      "outside": outside,
      "estimatedMinutes": estimatedMinutes,
      "groupedTasks": relatedTasks,
    };

    final reply = SmartPlanningResponseBuilder.askDurationValidation(
      relatedTasks: relatedTasks,
      hasGroupedTasks: hasGroupedTasks,
      taskTitle: task.title,
      estimatedMinutes: estimatedMinutes,
    );

    addAssistantMessage(reply);
    return true;
  }

  Future<List<Map<String, dynamic>>> buildCurrentPlanningReasoning() async {
    final rawMemories = await MemoryService.getMemories();

    final savedMemories = rawMemories.map((memory) {
      return {
        "text": memory["text"]?.toString() ?? "",
        "category": memory["category"]?.toString() ?? "personal",
        "importance":
            int.tryParse(memory["importance"]?.toString() ?? "0") ?? 0,
      };
    }).toList();

    final relevantMemories =
        MemoryContextBuilderService.buildRelevantMemoryPayload(
      memories: savedMemories,
      limit: 12,
    );

    final memoryReasoning =
        MemoryReasoningService.buildReasoning(relevantMemories);

    final profileReasoning =
        ProfileReasoningService.buildReasoning(widget.profile);

    return [
      ...profileReasoning,
      ...memoryReasoning,
    ];
  }

  Future<List<Map<String, dynamic>>> buildCurrentMemoryReasoning() async {
    return buildCurrentPlanningReasoning();
  }

  Future<bool> tryCompletePendingDurationPlanning(String text) async {
    final pending = pendingDurationPlanningTask;

    if (pending == null) return false;

    final task = pending["task"];

    if (task is! TaskModel) {
      pendingDurationPlanningTask = null;
      return false;
    }

    final originalMessage = pending["originalMessage"]?.toString() ?? "";
    final outside = pending["outside"] == true;
    final estimatedMinutes =
        int.tryParse(pending["estimatedMinutes"]?.toString() ?? "0") ?? 0;
    final rawGroupedTasks = pending["groupedTasks"];
    final groupedTasks = rawGroupedTasks is List<TaskModel>
        ? rawGroupedTasks
        : <TaskModel>[task];

    int selectedMinutes = 0;

    if (PlannerEngineService.isPositiveAnswer(text)) {
      selectedMinutes = estimatedMinutes;
    } else {
      selectedMinutes = parseDurationMinutes(text);

      if (selectedMinutes <= 0) {
        selectedMinutes = SmartPlanningService.parseTravelMinutes(text);
      }
    }

    if (selectedMinutes <= 0) {
      final reply = SmartPlanningResponseBuilder.askDurationExample();

      addAssistantMessage(reply);
      return true;
    }

    pendingDurationPlanningTask = null;

    if (outside) {
      pendingTravelPlanningTask = {
        "task": task,
        "originalMessage": originalMessage,
        "actionMinutes": selectedMinutes,
        "groupedTasks": groupedTasks,
      };

      final reply = SmartPlanningResponseBuilder.askTravelForOutsideTask(
        task.title,
      );

      addAssistantMessage(reply);
      return true;
    }

    final proposal = await PlanningProposalService.buildFromDurationPlanning(
      task: task,
      originalMessage: originalMessage,
      actionMinutes: selectedMinutes,
      memoryReasoning: await buildCurrentMemoryReasoning(),
    );

    if (!proposal.canPropose) {
      addAssistantMessage(proposal.confirmationMessage);
      return true;
    }

    pendingSmartPlanningProposal = proposal;
    addAssistantMessage(proposal.confirmationMessage);
    return true;
  }

  Future<bool> tryCompletePendingTravelPlanning(String text) async {
    final pending = pendingTravelPlanningTask;

    if (pending == null) return false;

    final travelGoMinutes = SmartPlanningService.parseTravelMinutes(text);

    if (travelGoMinutes <= 0) {
      final reply = SmartPlanningResponseBuilder.askTravelDurationExample();

      addAssistantMessage(reply);
      return true;
    }

    final task = pending["task"];

    if (task is! TaskModel) {
      pendingTravelPlanningTask = null;
      return false;
    }

    final originalMessage = pending["originalMessage"]?.toString() ?? "";
    final actionMinutes =
        int.tryParse(pending["actionMinutes"]?.toString() ?? "0") ?? 0;
    final rawGroupedTasks = pending["groupedTasks"];
    final groupedTasks = rawGroupedTasks is List<TaskModel>
        ? rawGroupedTasks
        : <TaskModel>[task];

    pendingTravelPlanningTask = null;

    final proposal = await PlanningProposalService.buildFromTravelPlanning(
      task: task,
      originalMessage: originalMessage,
      actionMinutes: actionMinutes,
      travelGoMinutes: travelGoMinutes,
      groupedTasks: groupedTasks,
      memoryReasoning: await buildCurrentMemoryReasoning(),
    );

    if (!proposal.canPropose) {
      addAssistantMessage(proposal.confirmationMessage);
      return true;
    }

    pendingSmartPlanningProposal = proposal;
    addAssistantMessage(proposal.confirmationMessage);
    return true;
  }

  Future<bool> tryCompletePendingConflictResolution(String text) async {
    if (pendingConflictResolutionEvent == null) return false;

    if (PlannerEngineService.isNegativeAnswer(text)) {
      final action = Map<String, dynamic>.from(pendingConflictResolutionEvent!);
      final title = action["title"]?.toString() ?? "ce rendez-vous";

      pendingConflictResolutionEvent = null;
      pendingDurationEvent = null;
      pendingTravelEvent = null;

      addAssistantMessage(
        ConflictEngineService.cancellationMessage(title),
      );

      return true;
    }

    final time = normalizeTime(text);

    if (time.isEmpty) {
      addAssistantMessage(
        ConflictEngineService.askNewTimeMessage(),
      );
      return true;
    }

    final action = Map<String, dynamic>.from(pendingConflictResolutionEvent!);
    action["time"] = time;
    action["durationMinutes"] = 0;
    action["travelMinutes"] = 0;

    pendingConflictResolutionEvent = null;
    pendingDurationEvent = action;

    addAssistantMessage(
      ConflictEngineService.askDurationMessage(
        action["title"]?.toString() ?? "ce rendez-vous",
      ),
    );

    return true;
  }

  Future<bool> tryCompletePendingDateEvent(String text) async {
    if (pendingDateEvent == null) return false;

    final action = Map<String, dynamic>.from(pendingDateEvent!);
    action["date"] = PlannerEngineService.extractDateFromText(text);
    pendingDateEvent = null;

    if (PlannerEngineService.saysUnknownTime(text)) {
      final title = action["title"]?.toString() ?? "ce rendez-vous";

      addAssistantMessage(
        "C’est noté pour « $title » 💕\n\n"
        "Je peux te proposer un créneau disponible si tu veux.",
      );

      return true;
    }

    final nextStep = PlannerEngineService.nextMissingEventStep(action);

    if (nextStep == "time") {
      pendingTimeEvent = action;

      final title = action["title"]?.toString() ?? "ce rendez-vous";

      addAssistantMessage(
        "C’est noté pour « $title » 💕\n\nÀ quelle heure est-il prévu ?",
      );

      return true;
    }

    return false;
  }

  Future<bool> tryCompletePendingTimeEvent(String text) async {
    if (pendingTimeEvent == null) return false;

    final action = Map<String, dynamic>.from(pendingTimeEvent!);

    if (PlannerEngineService.saysUnknownTime(text)) {
      pendingTimeEvent = null;

      final title = action["title"]?.toString() ?? "ce rendez-vous";
      final date = action["date"]?.toString() ?? "";

      pendingDurationPlanningTask = {
        "task": TaskModel(
          title: title,
          category: action["category"]?.toString() ?? "Personnel",
          isDone: false,
          createdAt: DateTime.now(),
          planning: date.isNotEmpty ? date : "Cette semaine",
        ),
        "originalMessage": "$title $date",
        "type": action["type"]?.toString() ?? "rendez-vous",
        "outside": true,
        "estimatedMinutes": 60,
        "groupedTasks": <TaskModel>[],
      };

      addAssistantMessage(
        "D’accord 💕 Je vais te proposer un créneau disponible pour « $title ».\n\n"
        "Combien de temps veux-tu prévoir pour ce rendez-vous ?",
      );

      return true;
    }

    final time = normalizeTime(text);

    if (time.isEmpty) {
      addAssistantMessage(
        "Dis-moi simplement l’heure, par exemple 10h, 14h30 ou 18h 💕",
      );
      return true;
    }

    action["time"] = time;
    pendingTimeEvent = null;

    final nextStep = PlannerEngineService.nextMissingEventStep(action);

    if (nextStep == "duration") {
      pendingDurationEvent = action;

      final title = action["title"]?.toString() ?? "ce rendez-vous";

      addAssistantMessage(
        "Parfait 💕\n\nCombien de temps veux-tu prévoir pour « $title » ?",
      );

      return true;
    }

    return false;
  }

  Future<bool> tryCompletePendingEventTravel(String text) async {
    if (pendingTravelEvent == null) return false;

    final action = Map<String, dynamic>.from(pendingTravelEvent!);

    if (PlannerEngineService.isNoTravelAnswer(text)) {
      action["travelMinutes"] = 0;
      pendingTravelEvent = null;

      final conflictText = await handleAction(action);
      final reply = conflictText.isNotEmpty
          ? conflictText
          : "C’est noté 💕 J’ai bloqué « ${action["title"]} » dans ton agenda.";

      addAssistantMessage(reply);
      return true;
    }

    final travelGoMinutes = SmartPlanningService.parseTravelMinutes(text);

    if (travelGoMinutes <= 0) {
      addAssistantMessage(
        "Dis-moi juste le temps du trajet aller, par exemple 10 min, "
        "15 min ou 25 min. Tu peux aussi répondre non 💕",
      );
      return true;
    }

    action["travelMinutes"] = travelGoMinutes * 2;
    pendingTravelEvent = null;

    final conflictText = await handleAction(action);
    final title = action["title"]?.toString() ?? "ce rendez-vous";

    final reply = conflictText.isNotEmpty
        ? conflictText
        : "C’est noté 💕 J’ai bloqué « $title » dans ton agenda, "
            "avec $travelGoMinutes min de trajet aller et "
            "$travelGoMinutes min de trajet retour.";

    addAssistantMessage(reply);
    return true;
  }

  Future<bool> tryCompletePendingDuration(String text) async {
    if (pendingDurationEvent == null) return false;

    final duration = parseDurationMinutes(text);

    if (duration <= 0) {
      const reply = "Dis-moi juste la durée, par exemple 30 min, 1h ou 1h30 💕";

      addAssistantMessage(reply);
      return true;
    }

    final action = Map<String, dynamic>.from(pendingDurationEvent!);
    action["durationMinutes"] = duration;
    action["needsDuration"] = false;
    pendingDurationEvent = null;

    final nextStep = PlannerEngineService.nextMissingEventStep(
      action,
      needsTravel: eventNeedsTravel(action),
    );

    if (nextStep == "travel") {
      pendingTravelEvent = action;

      final title = action["title"]?.toString() ?? "ce rendez-vous";

      addAssistantMessage(
        "Parfait 💕 Et pour « $title », combien de temps faut-il prévoir "
        "pour le trajet aller ?\n\n"
        "Tu peux répondre par exemple : 10 min, 15 min, 25 min, ou non.",
      );

      return true;
    }

    if (nextStep == "ready") {
      final conflictText = await handleAction(action);

      final reply = conflictText.isNotEmpty
          ? conflictText
          : "C’est noté 💕 J’ai bloqué ce créneau dans l’agenda.";

      addAssistantMessage(reply);
      return true;
    }

    return false;
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    currentUserMessage = text;

    if (text.isEmpty || loading) return;

    controller.clear();

    setState(() {
      messages.add({"role": "user", "text": text});
      loading = true;
    });

    saveMessageInBackground(role: "user", text: text);

    try {
      final completedConflictResolution =
          await tryCompletePendingConflictResolution(text);
      if (completedConflictResolution) return;

      final completedDateEvent = await tryCompletePendingDateEvent(text);
      if (completedDateEvent) return;

      final completedTimeEvent = await tryCompletePendingTimeEvent(text);
      if (completedTimeEvent) return;

      final completedSmartPlanning =
          await tryCompletePendingSmartPlanning(text);

      if (completedSmartPlanning) return;

      final completedPlanningRequest =
          await tryCompletePendingPlanningRequest(text);

      if (completedPlanningRequest) return;

      final completedDurationPlanning =
          await tryCompletePendingDurationPlanning(text);

      if (completedDurationPlanning) return;

      final completedTravelPlanning =
          await tryCompletePendingTravelPlanning(text);

      if (completedTravelPlanning) return;

      final completedEventTravel = await tryCompletePendingEventTravel(text);
      if (completedEventTravel) return;

      final completedPending = await tryCompletePendingDuration(text);
      if (completedPending) return;

      if (MemoryPipelineService.shouldProcessMemory(text)) {
        final memory = MemoryPipelineService.buildMemory(text);

        await MemoryService.saveMemory(
          text: memory["text"]?.toString() ?? text,
          category: memory["category"]?.toString() ?? "personal",
        );
      }

      final rawMemories = await MemoryService.getMemories();
      final savedMemories = rawMemories.map((memory) {
        return {
          "text": memory["text"]?.toString() ?? "",
          "category": memory["category"]?.toString() ?? "personal",
          "importance":
              int.tryParse(memory["importance"]?.toString() ?? "0") ?? 0,
        };
      }).toList();

      final relevantMemories =
          MemoryContextBuilderService.buildRelevantMemoryPayload(
        memories: savedMemories,
        limit: 12,
      );

      final memoryReasoning =
          MemoryReasoningService.buildReasoning(relevantMemories);

      final savedEvents = await EventService.getEvents();
      final existingEvents = savedEvents.map((event) {
        return {
          "title": event.title,
          "date": event.date,
          "time": event.time,
          "startDateTimeIso": event.startDateTimeIso,
          "endTime": event.endTime,
          "endDateTimeIso": event.endDateTimeIso,
          "durationMinutes": event.durationMinutes,
        };
      }).toList();

      final response = await http.post(
        Uri.parse(
          "https://us-central1-zelia-ai-app.cloudfunctions.net/chatWithZeliaHttp",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": text,
          "profile": widget.profile.toJson(),
          "memories": relevantMemories,
          "memoryReasoning": memoryReasoning,
          "events": existingEvents,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Erreur serveur ${response.statusCode}");
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      String reply = data["reply"]?.toString() ?? "C’est noté 💕";
      final actions = data["actions"];
      final newMemories = data["memories"];

      final actionMessages = <String>[];
      final shoppingTitles = <String>[];
      final taskTitles = <String>[];
      final eventTitles = <String>[];

      if (actions is List) {
        for (final action in actions) {
          if (action is Map) {
            final type = action["type"]?.toString() ?? "";
            final title = action["title"]?.toString() ?? "";

            if (type == "shopping" && title.trim().isNotEmpty) {
              shoppingTitles.add(title);
            }

            if (type == "task" && title.trim().isNotEmpty) {
              taskTitles.add(title);
            }

            if (type == "event" && title.trim().isNotEmpty) {
              eventTitles.add(title);
            }
          }

          final actionText = await handleAction(action);
          if (actionText.isNotEmpty) actionMessages.add(actionText);
        }
      }

      if (newMemories is List) {
        for (final memory in newMemories) {
          await handleMemory(memory);
        }
      }

      if (actionMessages.isNotEmpty) {
        reply = actionMessages.join("\n\n");
      } else if (actions is List && actions.isNotEmpty) {
        final planningTitle = pendingSmartPlanningTask != null
            ? (pendingSmartPlanningTask!["task"] as TaskModel).title
            : null;

        reply = ZeliaResponseBuilder.buildGroupedActionReply(
          shoppingTitles: shoppingTitles,
          taskTitles: taskTitles,
          eventTitles: eventTitles,
          planningTitle: planningTitle,
        );
      }

      addAssistantMessage(reply);
    } catch (e) {
      final errorText = "Je rencontre un petit souci : $e";
      addAssistantMessage(errorText);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> handleMemory(dynamic memory) async {
    if (memory is! Map) return;

    final text = memory["text"]?.toString() ?? "";

    if (text.trim().isEmpty) return;
    if (!MemoryPipelineService.shouldProcessMemory(text)) return;

    final builtMemory = MemoryPipelineService.buildMemory(text);

    await MemoryService.saveMemory(
      text: builtMemory["text"]?.toString() ?? text,
      category: builtMemory["category"]?.toString() ?? "personal",
    );
  }

  Future<void> startListening() async {
    final available = await voiceService.init();
    if (!available) return;

    setState(() {
      isListening = true;
    });

    await voiceService.listen(
      onResult: (text) {
        setState(() {
          controller.text = text;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        });
      },
    );
  }

  Future<void> stopListening() async {
    await voiceService.stop();
    setState(() {
      isListening = false;
    });
  }

  Future<String> handleAction(dynamic action) async {
    final result = await ActionHandlerService.handleAction(
      action: action,
      currentUserMessage: currentUserMessage,
      normalizeTime: normalizeTime,
      parseDurationMinutes: parseDurationMinutes,
      weekdayFromText: weekdayFromText,
      messageLooksRecurringWeekly: messageLooksRecurringWeekly,
      nextDateForWeekday: nextDateForWeekday,
      eventNeedsTravel: eventNeedsTravel,
      buildStartDateTimeIso: buildStartDateTimeIso,
      buildEndDateTimeIso: buildEndDateTimeIso,
      endTimeFromDuration: endTimeFromDuration,
    );

    if (result.pendingDateEvent != null) {
      pendingDateEvent = result.pendingDateEvent;
    }

    if (result.pendingTimeEvent != null) {
      pendingTimeEvent = result.pendingTimeEvent;
    }

    if (result.pendingDurationEvent != null) {
      pendingDurationEvent = result.pendingDurationEvent;
    }

    if (result.pendingTravelEvent != null) {
      pendingTravelEvent = result.pendingTravelEvent;
    }

    if (result.pendingConflictResolutionEvent != null) {
      pendingConflictResolutionEvent = result.pendingConflictResolutionEvent;
    }

    if (result.pendingSmartPlanningTask != null) {
      pendingSmartPlanningTask = result.pendingSmartPlanningTask;
    }

    return result.message;
  }

  Widget buildMessage(Map<String, dynamic> message) {
    final isUser = message["role"] == "user";

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFC78372) : Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          message["text"]?.toString() ?? "",
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF3D241E),
            fontSize: 16,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget buildSendOrMicButton() {
    final hasText = controller.text.trim().isNotEmpty;

    return CircleAvatar(
      radius: 28,
      backgroundColor: isListening ? Colors.red : const Color(0xFFC78372),
      child: IconButton(
        onPressed: loading
            ? null
            : () async {
                if (hasText) {
                  await stopListening();
                  await sendMessage();
                } else {
                  if (isListening) {
                    await stopListening();
                  } else {
                    await startListening();
                  }
                }
              },
        icon: Icon(
          hasText
              ? Icons.send
              : isListening
                  ? Icons.stop
                  : Icons.mic,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    voiceService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EFEA),
      appBar: AppBar(
        title: const Text("Zelia 💕"),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return buildMessage(messages[index]);
              },
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: (_) {
                      setState(() {});
                    },
                    onSubmitted: (_) => sendMessage(),
                    decoration: InputDecoration(
                      hintText:
                          isListening ? "J'écoute..." : "Parle à Zelia 💕",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                buildSendOrMicButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
