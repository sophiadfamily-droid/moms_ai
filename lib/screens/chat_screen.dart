import 'dart:convert';

import '../services/chat_service.dart';
import '../services/chat_planning_helper_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import '../models/task_model.dart';
import '../models/event_model.dart';
import '../models/planning_draft_model.dart';

import '../services/event_service.dart';
import '../services/event_confirmation_service.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import '../services/memory_service.dart';
import '../services/memory_pipeline_service.dart';
import '../services/memory_context_builder_service.dart';
import '../services/memory_reasoning_service.dart';
import '../services/smart_planning_service.dart';
import '../services/smart_planning_response_builder.dart';
import '../services/planning_proposal_service.dart';
import '../services/planning_proposal_engine.dart';
import '../services/planning_proposal_selection_service.dart';
import '../services/selected_slot_schedule_service.dart';
import '../services/selected_slot_revalidation_service.dart';
import '../services/planning_draft_service.dart';
import '../services/profile_reasoning_service.dart';
import '../services/profile_context_builder_service.dart';
import '../services/planner_engine_service.dart';
import '../services/conflict_engine_service.dart';
import '../services/zelia_response_builder.dart';
import '../services/action_handler_service.dart';
import '../services/zelia_action_guard_service.dart';
import '../services/natural_date_service.dart';

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

  bool loading = false;
  bool isListening = false;

  Map<String, dynamic>? pendingDateEvent;
  Map<String, dynamic>? pendingTimeEvent;
  Map<String, dynamic>? pendingDurationEvent;
  Map<String, dynamic>? pendingTravelEvent;
  Map<String, dynamic>? pendingConflictResolutionEvent;
  EventModel? pendingConfirmationEvent;
  SmartPlanningProposal? pendingSmartPlanningProposal;
  Map<String, dynamic>? pendingSmartPlanningTask;
  Map<String, dynamic>? pendingDurationPlanningTask;
  Map<String, dynamic>? pendingTravelPlanningTask;
  List<PlanningProposalOption> pendingPlanningProposalOptions = [];
  Map<String, dynamic>? pendingPlanningProposalContext;
  Map<String, dynamic>? pendingSelectedSlotEvent;
  Map<String, dynamic>? pendingSlotProposalRequest;
  Map<String, dynamic>? pendingAlternativePlanningTask;

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
    try {
      await ChatService.saveMessage(
        conversationId: currentConversationId,
        role: role,
        text: text,
      );
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

  Future<bool> tryShowMultiSlotProposal({
    required TaskModel task,
    required String originalMessage,
    required int actionMinutes,
    required int travelGoMinutes,
    required int travelBackMinutes,
    required List<TaskModel> groupedTasks,
  }) async {
    final targetDate = SmartPlanningService.targetDateFromText(
      originalMessage,
      task,
    );

    final type = SmartPlanningService.detectTaskType(
      originalMessage,
      task,
    );

    final marginMinutes = SmartPlanningService.defaultMarginMinutes(type);
    final totalMinutes =
        actionMinutes + travelGoMinutes + travelBackMinutes + marginMinutes;

    final result = await PlanningProposalEngine.findBestOptions(
      startDate: targetDate,
      totalMinutes: totalMinutes,
      reasoning: await buildCurrentMemoryReasoning(),
      searchDays: 21,
      maxOptions: 3,
    );

    if (!result.hasOptions || result.options.isEmpty) {
      return false;
    }

    pendingPlanningProposalOptions = result.options;
    pendingPlanningProposalContext = {
      "task": task,
      "originalMessage": originalMessage,
      "actionMinutes": actionMinutes,
      "travelGoMinutes": travelGoMinutes,
      "travelBackMinutes": travelBackMinutes,
      "marginMinutes": marginMinutes,
      "groupedTasks": groupedTasks,
    };

    final lines = <String>[
      result.options.length > 1
          ? "J’ai trouvé plusieurs créneaux possibles :"
          : "J’ai trouvé ce créneau possible :",
      "",
    ];

    for (var index = 0; index < result.options.length; index++) {
      final option = result.options[index];
      lines.add("${index + 1}. ${option.label}");
    }

    lines.add("");
    lines.add("Lequel tu préfères ?");

    addAssistantMessage(lines.join("\n"));
    return true;
  }

  Future<bool> tryCompletePlanningProposalSelection(String text) async {
    if (pendingPlanningProposalOptions.isEmpty ||
        pendingPlanningProposalContext == null) {
      return false;
    }

    final index = PlanningProposalSelectionService.extractIndex(
      text,
      pendingPlanningProposalOptions,
    );

    if (index == null || index >= pendingPlanningProposalOptions.length) {
      return false;
    }

    final selectedOption = pendingPlanningProposalOptions[index];
    final context = Map<String, dynamic>.from(
      pendingPlanningProposalContext ?? {},
    );

    final task = context["task"];

    if (task is! TaskModel) {
      pendingPlanningProposalOptions = [];
      pendingPlanningProposalContext = null;

      addAssistantMessage(
        "Je n’ai pas pu finaliser ce créneau, il me manque le rendez-vous à créer.",
      );
      return true;
    }

    final durationMinutes =
        int.tryParse(context["actionMinutes"]?.toString() ?? "0") ?? 0;
    final travelGoMinutes =
        int.tryParse(context["travelGoMinutes"]?.toString() ?? "0") ?? 0;
    final travelBackMinutes =
        int.tryParse(context["travelBackMinutes"]?.toString() ?? "0") ?? 0;
    final marginMinutes =
        int.tryParse(context["marginMinutes"]?.toString() ?? "0") ?? 0;

    if (durationMinutes <= 0) {
      pendingPlanningProposalOptions = [];
      pendingPlanningProposalContext = null;

      addAssistantMessage(
        "Je n’ai pas pu finaliser ce créneau, car la durée du rendez-vous est invalide.",
      );
      return true;
    }

    final schedule = SelectedSlotScheduleService.build(
      protectedStart: selectedOption.start,
      durationMinutes: durationMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      marginMinutes: marginMinutes,
    );

    if (schedule == null) {
      pendingPlanningProposalOptions = [];
      pendingPlanningProposalContext = null;

      addAssistantMessage(
        "Je n’ai pas pu calculer correctement les horaires de ce créneau.",
      );
      return true;
    }

    final appointmentStartTime =
        SmartPlanningService.formatIsoTime(schedule.appointmentStart);
    final appointmentEndTime =
        SmartPlanningService.formatIsoTime(schedule.appointmentEnd);
    final protectedEndTime =
        SmartPlanningService.formatIsoTime(schedule.protectedEnd);

    pendingSelectedSlotEvent = {
      "step": "confirmation",
      "task": task,
      "option": selectedOption.toJson(),
      "originalMessage": context["originalMessage"]?.toString() ?? "",
      "durationMinutes": durationMinutes,
      "travelGoMinutes": travelGoMinutes,
      "travelBackMinutes": travelBackMinutes,
      "marginMinutes": marginMinutes,
    };

    pendingPlanningProposalOptions = [];
    pendingPlanningProposalContext = null;

    addAssistantMessage(
      [
        "Je récapitule avant de réserver 💕",
        "",
        "• Rendez-vous : ${task.title}",
        "• Date : ${selectedOption.dateIso}",
        "• Départ prévu : ${selectedOption.startTime}",
        "• Rendez-vous : $appointmentStartTime à $appointmentEndTime",
        "• Retour et marge terminés à : $protectedEndTime",
        "• Durée du rendez-vous : ${SmartPlanningService.durationLabel(durationMinutes)}",
        "• Trajet aller : ${SmartPlanningService.durationLabel(travelGoMinutes)}",
        "• Trajet retour : ${SmartPlanningService.durationLabel(travelBackMinutes)}",
        if (marginMinutes > 0)
          "• Marge : ${SmartPlanningService.durationLabel(marginMinutes)}",
        "",
        "Tu confirmes que je réserve ce créneau ?",
      ].join("\n"),
    );

    return true;
  }

  Future<bool> tryCompletePendingSelectedSlotEvent(String text) async {
    final pending = pendingSelectedSlotEvent;

    if (pending == null) return false;

    final task = pending["task"];
    final optionRaw = pending["option"];

    if (task is! TaskModel || optionRaw is! Map) {
      pendingSelectedSlotEvent = null;
      return false;
    }

    final option = Map<String, dynamic>.from(optionRaw);
    final step = pending["step"]?.toString() ?? "duration";

    if (step == "duration") {
      var durationMinutes =
          ChatPlanningHelperService.parseDurationMinutes(text);

      if (durationMinutes <= 0) {
        durationMinutes = SmartPlanningService.parseTravelMinutes(text);
      }

      if (durationMinutes <= 0) {
        addAssistantMessage(
          "Dis-moi simplement la durée du rendez-vous, par exemple 30 min, 45 min ou 1 heure 💕",
        );
        return true;
      }

      pendingSelectedSlotEvent = {
        ...pending,
        "step": "travel",
        "durationMinutes": durationMinutes,
      };

      addAssistantMessage(
        "Très bien 💕\n\nCombien de temps faut-il prévoir pour le trajet aller ? "
        "Tu peux répondre par exemple 10 min, 20 min, ou 0 si aucun trajet.",
      );

      return true;
    }

    if (step == "travel") {
      final lower = text.trim().toLowerCase();

      var travelGoMinutes = 0;

      if (PlannerEngineService.isNoTravelAnswer(lower) ||
          lower == "0" ||
          lower == "aucun" ||
          lower == "pas de trajet") {
        travelGoMinutes = 0;
      } else {
        travelGoMinutes = SmartPlanningService.parseTravelMinutes(text);
      }

      if (travelGoMinutes < 0) {
        travelGoMinutes = 0;
      }

      final durationMinutes =
          int.tryParse(pending["durationMinutes"]?.toString() ?? "0") ?? 0;

      if (durationMinutes <= 0) {
        pendingSelectedSlotEvent = {
          ...pending,
          "step": "duration",
        };

        addAssistantMessage(
          "Il me manque encore la durée du rendez-vous. Combien de temps veux-tu prévoir ?",
        );
        return true;
      }

      pendingSelectedSlotEvent = {
        ...pending,
        "step": "travelBack",
        "travelGoMinutes": travelGoMinutes,
      };

      addAssistantMessage(
        "Et pour le trajet retour, combien de temps faut-il prévoir ? "
        "Tu peux répondre pareil, 0, 15 min, 30 min, etc. 💕",
      );

      return true;
    }

    if (step == "travelBack") {
      final lower = text.trim().toLowerCase();
      final travelGoMinutes =
          int.tryParse(pending["travelGoMinutes"]?.toString() ?? "0") ?? 0;

      var travelBackMinutes = 0;

      if (lower.contains("pareil") ||
          lower.contains("même") ||
          lower.contains("meme") ||
          lower.contains("identique")) {
        travelBackMinutes = travelGoMinutes;
      } else if (PlannerEngineService.isNoTravelAnswer(lower) ||
          lower == "0" ||
          lower == "aucun" ||
          lower == "pas de trajet") {
        travelBackMinutes = 0;
      } else {
        travelBackMinutes = SmartPlanningService.parseTravelMinutes(text);
      }

      final durationMinutes =
          int.tryParse(pending["durationMinutes"]?.toString() ?? "0") ?? 0;

      final marginMinutes =
          int.tryParse(pending["marginMinutes"]?.toString() ?? "0") ?? 0;
      final start = DateTime.tryParse(option["start"]?.toString() ?? "");
      final schedule = SelectedSlotScheduleService.build(
        protectedStart: start,
        durationMinutes: durationMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
      );

      if (schedule == null) {
        addAssistantMessage(
          "Je n’ai pas pu calculer correctement les horaires de ce créneau.",
        );
        return true;
      }

      final appointmentStartTime =
          SmartPlanningService.formatIsoTime(schedule.appointmentStart);
      final appointmentEndTime =
          SmartPlanningService.formatIsoTime(schedule.appointmentEnd);
      final protectedEndTime =
          SmartPlanningService.formatIsoTime(schedule.protectedEnd);

      pendingSelectedSlotEvent = {
        ...pending,
        "step": "confirmation",
        "travelGoMinutes": travelGoMinutes,
        "travelBackMinutes": travelBackMinutes,
      };

      addAssistantMessage(
        "Je récapitule avant de réserver 💕\n\n"
        "• Rendez-vous : ${task.title}\n"
        "• Date : ${option["dateIso"]}\n"
        "• Départ prévu : ${option["startTime"]}\n"
        "• Rendez-vous : $appointmentStartTime à $appointmentEndTime\n"
        "• Durée du rendez-vous : ${SmartPlanningService.durationLabel(durationMinutes)}\n"
        "• Trajet aller : ${SmartPlanningService.durationLabel(travelGoMinutes)}\n"
        "• Trajet retour : ${SmartPlanningService.durationLabel(travelBackMinutes)}\n"
        "• Retour et marge terminés à : $protectedEndTime\n\n"
        "Tu confirmes que je réserve ce créneau ?",
      );

      return true;
    }

    if (step == "confirmation") {
      if (PlannerEngineService.isNegativeAnswer(text)) {
        pendingSelectedSlotEvent = null;

        addAssistantMessage(
          "D’accord 💕 Je ne réserve pas ce rendez-vous.",
        );
        return true;
      }

      if (!PlannerEngineService.isPositiveAnswer(text)) {
        addAssistantMessage(
          "Réponds simplement oui pour réserver, ou non pour annuler 💕",
        );
        return true;
      }

      final durationMinutes =
          int.tryParse(pending["durationMinutes"]?.toString() ?? "0") ?? 0;
      final travelGoMinutes =
          int.tryParse(pending["travelGoMinutes"]?.toString() ?? "0") ?? 0;

      final start = DateTime.tryParse(option["start"]?.toString() ?? "");

      if (start == null || durationMinutes <= 0) {
        pendingSelectedSlotEvent = null;

        addAssistantMessage(
          "Je n’ai pas pu finaliser ce rendez-vous, il me manque une information essentielle.",
        );
        return true;
      }

      final travelBackMinutes =
          int.tryParse(pending["travelBackMinutes"]?.toString() ?? "0") ?? 0;

      final marginMinutes =
          int.tryParse(pending["marginMinutes"]?.toString() ?? "0") ?? 0;
      final totalTravel = travelGoMinutes + travelBackMinutes;
      final schedule = SelectedSlotScheduleService.build(
        protectedStart: start,
        durationMinutes: durationMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        marginMinutes: marginMinutes,
      );

      if (schedule == null) {
        pendingSelectedSlotEvent = null;

        addAssistantMessage(
          "Je n’ai pas pu finaliser ce rendez-vous, car ses horaires sont invalides.",
        );
        return true;
      }

      final dateIso =
          SmartPlanningService.formatIsoDate(schedule.appointmentStart);
      final startTime =
          SmartPlanningService.formatIsoTime(schedule.appointmentStart);
      final endTime =
          SmartPlanningService.formatIsoTime(schedule.appointmentEnd);

      final event = EventModel(
        title: task.title,
        date: dateIso,
        time: startTime,
        endTime: endTime,
        durationMinutes: durationMinutes,
        travelMinutes: totalTravel,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        usesSeparateTravelTimes: true,
        marginMinutes: marginMinutes,
        departureContext: "previous_event",
        arrivalContext: "next_event",
        startDateTimeIso: "${dateIso}T$startTime:00",
        endDateTimeIso: "${dateIso}T$endTime:00",
        category: task.category,
        notes: "Planifié par Zelia depuis une proposition multi-créneaux.\n"
            "Durée du rendez-vous : $durationMinutes min\n"
            "Trajet aller estimé : $travelGoMinutes min\n"
            "Trajet retour estimé : $travelBackMinutes min",
        createdAt: DateTime.now(),
      );

      final totalMinutes =
          durationMinutes + travelGoMinutes + travelBackMinutes + marginMinutes;

      final revalidation = await SelectedSlotRevalidationService.revalidate(
        candidate: event,
        protectedStart: schedule.protectedStart,
        totalMinutes: totalMinutes,
        reasoning: await buildCurrentPlanningReasoning(),
      );

      if (!revalidation.isAvailable) {
        pendingSelectedSlotEvent = null;

        final alternatives = revalidation.alternatives;

        if (alternatives.hasOptions && alternatives.options.isNotEmpty) {
          pendingPlanningProposalOptions = alternatives.options;
          pendingPlanningProposalContext = {
            "task": task,
            "originalMessage":
                pending["originalMessage"]?.toString() ?? task.notes,
            "actionMinutes": durationMinutes,
            "travelGoMinutes": travelGoMinutes,
            "travelBackMinutes": travelBackMinutes,
            "marginMinutes": marginMinutes,
            "groupedTasks": <TaskModel>[task],
          };

          final lines = <String>[
            "Ce créneau vient d’être pris par « ${revalidation.conflictEvent?.title ?? "un autre événement"} » 💕",
            "",
            "Je ne l’ai donc pas réservé. J’ai recherché immédiatement de nouvelles possibilités :",
            "",
          ];

          for (var index = 0; index < alternatives.options.length; index++) {
            lines.add(
              "${index + 1}. ${alternatives.options[index].label}",
            );
          }

          lines.add("");
          lines.add("Réponds 1, 2 ou 3 pour choisir un nouveau créneau.");

          addAssistantMessage(lines.join("\n"));
          return true;
        }

        pendingPlanningProposalOptions = [];
        pendingPlanningProposalContext = null;

        addAssistantMessage(
          "Je n’ai pas réservé ce créneau, car il est maintenant en conflit avec "
          "« ${revalidation.conflictEvent?.title ?? "un autre événement"} » 💕\n\n"
          "Je n’ai pas trouvé d’autre disponibilité réaliste pour le moment.",
        );
        return true;
      }

      await EventService.addEvent(event);

      await NotificationService.showNotification(
        title: "Créneau réservé 📅",
        body: task.title,
      );

      pendingSelectedSlotEvent = null;

      addAssistantMessage(
        "C’est fait 💕 J’ai réservé « ${task.title} » le $dateIso de $startTime à $endTime dans ton agenda.",
      );

      return true;
    }

    return false;
  }

  Future<bool> tryCompletePendingAlternativePlanning(String text) async {
    final pending = pendingAlternativePlanningTask;

    if (pending == null) return false;

    if (PlannerEngineService.isNegativeAnswer(text)) {
      pendingAlternativePlanningTask = null;
      addAssistantMessage(
        "D’accord 💕 Je ne cherche pas d’autre jour pour le moment.",
      );
      return true;
    }

    if (!PlannerEngineService.isPositiveAnswer(text)) {
      addAssistantMessage(
        "Dis-moi simplement oui si tu veux que je cherche un autre jour, "
        "ou non si tu préfères arrêter ici 💕",
      );
      return true;
    }

    final task = pending["task"];

    if (task is! TaskModel) {
      pendingAlternativePlanningTask = null;
      return false;
    }

    final failedDateText = pending["failedDate"]?.toString() ?? "";
    final failedDate = DateTime.tryParse(failedDateText) ?? DateTime.now();

    final actionMinutes =
        int.tryParse(pending["actionMinutes"]?.toString() ?? "0") ?? 0;
    final travelGoMinutes =
        int.tryParse(pending["travelGoMinutes"]?.toString() ?? "0") ?? 0;
    final travelBackMinutes =
        int.tryParse(pending["travelBackMinutes"]?.toString() ?? "0") ?? 0;

    final rawGroupedTasks = pending["groupedTasks"];
    final groupedTasks = rawGroupedTasks is List<TaskModel>
        ? rawGroupedTasks
        : <TaskModel>[task];

    SmartPlanningProposal? foundProposal;
    DateTime lastTriedDate = failedDate;

    for (var dayOffset = 1; dayOffset <= 14; dayOffset++) {
      final nextDate = failedDate.add(Duration(days: dayOffset));
      lastTriedDate = nextDate;
      final nextDateIso = nextDate.toIso8601String().substring(0, 10);

      final proposal = await PlanningProposalService.buildFromTravelPlanning(
        task: task.copyWith(
          planning: nextDateIso,
          dueDate: nextDateIso,
        ),
        originalMessage: "${task.title} $nextDateIso",
        actionMinutes: actionMinutes,
        travelGoMinutes: travelGoMinutes,
        travelBackMinutes: travelBackMinutes,
        groupedTasks: groupedTasks,
        memoryReasoning: await buildCurrentMemoryReasoning(),
      );

      if (proposal.canPropose) {
        foundProposal = proposal;
        break;
      }
    }

    if (foundProposal == null) {
      pendingAlternativePlanningTask = {
        ...pending,
        "failedDate": lastTriedDate.toIso8601String().substring(0, 10),
      };

      addAssistantMessage(
        "Je n’ai pas trouvé de créneau réaliste sur les 14 prochains jours 💕\n\n"
        "On peut soit chercher plus loin, soit réduire la durée ou le temps de trajet.",
      );
      return true;
    }

    pendingAlternativePlanningTask = null;
    pendingSmartPlanningProposal = foundProposal;

    addAssistantMessage(
      "J’ai trouvé une autre possibilité 💕\n\n"
      "${foundProposal.confirmationMessage}",
    );

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

  bool looksLikeSlotProposalRequest(String text) {
    final lower = text.toLowerCase();

    final hasProposalIntent = lower.contains("propose-moi un créneau") ||
        lower.contains("propose moi un créneau") ||
        lower.contains("propose-moi un creneau") ||
        lower.contains("propose moi un creneau") ||
        lower.contains("trouve-moi un créneau") ||
        lower.contains("trouve moi un créneau") ||
        lower.contains("trouve-moi un creneau") ||
        lower.contains("trouve moi un creneau") ||
        lower.contains("cherche-moi un créneau") ||
        lower.contains("cherche moi un créneau") ||
        lower.contains("place-moi un rendez-vous") ||
        lower.contains("place moi un rendez-vous") ||
        lower.contains("quand est-ce que je peux") ||
        lower.contains("quand est ce que je peux");

    final hasAppointmentIntent = lower.contains("rendez-vous") ||
        lower.contains("rendez vous") ||
        lower.contains("rdv") ||
        lower.contains("médecin") ||
        lower.contains("medecin") ||
        lower.contains("dentiste") ||
        lower.contains("consultation") ||
        lower.contains("réunion") ||
        lower.contains("reunion") ||
        lower.contains("coiffeur") ||
        lower.contains("coiffeuse") ||
        lower.contains("esthéticienne") ||
        lower.contains("estheticienne") ||
        lower.contains("ongles") ||
        lower.contains("garage") ||
        lower.contains("contrôle technique") ||
        lower.contains("controle technique");

    return hasProposalIntent && hasAppointmentIntent;
  }

  String titleFromSlotProposalRequest(String text) {
    final lower = text.toLowerCase();

    if (lower.contains("médecin") || lower.contains("medecin")) {
      return "Médecin";
    }

    if (lower.contains("dentiste")) {
      return "Dentiste";
    }

    if (lower.contains("pédiatre") || lower.contains("pediatre")) {
      return "Pédiatre";
    }

    if (lower.contains("réunion") || lower.contains("reunion")) {
      return "Réunion";
    }

    if (lower.contains("coiffeur") || lower.contains("coiffeuse")) {
      return "Coiffeur";
    }

    if (lower.contains("esthéticienne") || lower.contains("estheticienne")) {
      return "Esthéticienne";
    }

    if (lower.contains("ongles")) {
      return "Ongles";
    }

    if (lower.contains("garage")) {
      return "Garage";
    }

    if (lower.contains("contrôle technique") ||
        lower.contains("controle technique")) {
      return "Contrôle technique";
    }

    return "Rendez-vous";
  }

  DateTime startDateForSlotProposalRequest(String text) {
    final lower = text.toLowerCase();
    final today = DateTime.now();
    final startToday = DateTime(today.year, today.month, today.day);

    if (lower.contains("semaine prochaine")) {
      final daysUntilNextMonday = (8 - startToday.weekday) % 7;
      final safeDays = daysUntilNextMonday == 0 ? 7 : daysUntilNextMonday;
      return startToday.add(Duration(days: safeDays));
    }

    final resolvedIsoDate = NaturalDateService.resolveDateFromText(text);
    final parsed = DateTime.tryParse(resolvedIsoDate);

    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    return startToday;
  }

  int defaultDurationForSlotProposalRequest(String text) {
    final parsed = ChatPlanningHelperService.parseDurationMinutes(text);

    if (parsed > 0) {
      return parsed;
    }

    final lower = text.toLowerCase();

    if (lower.contains("médecin") ||
        lower.contains("medecin") ||
        lower.contains("dentiste") ||
        lower.contains("pédiatre") ||
        lower.contains("pediatre") ||
        lower.contains("consultation")) {
      return 60;
    }

    if (lower.contains("réunion") || lower.contains("reunion")) {
      return 60;
    }

    return 60;
  }

  Future<bool> tryStartSlotProposalRequest(String text) async {
    if (!looksLikeSlotProposalRequest(text)) {
      return false;
    }

    final startDate = startDateForSlotProposalRequest(text);
    final title = titleFromSlotProposalRequest(text);

    pendingSlotProposalRequest = {
      "step": "duration",
      "title": title,
      "originalMessage": text,
      "startDate": SmartPlanningService.formatIsoDate(startDate),
    };

    addAssistantMessage(
      [
        "D’accord 💕 Pour te proposer un vrai créneau disponible pour « $title », j’ai d’abord besoin de la durée du rendez-vous.",
        "",
        "Combien de temps veux-tu prévoir ?",
      ].join("\n"),
    );

    return true;
  }

  Future<bool> tryCompletePendingSlotProposalRequest(String text) async {
    final pending = pendingSlotProposalRequest;

    if (pending == null) return false;

    final step = pending["step"]?.toString() ?? "duration";
    final title = pending["title"]?.toString() ?? "Rendez-vous";
    final originalMessage = pending["originalMessage"]?.toString() ?? "";
    final startDateIso = pending["startDate"]?.toString() ?? "";
    final startDate = DateTime.tryParse(startDateIso) ?? DateTime.now();

    if (step == "duration") {
      var durationMinutes =
          ChatPlanningHelperService.parseDurationMinutes(text);

      if (durationMinutes <= 0) {
        durationMinutes = SmartPlanningService.parseTravelMinutes(text);
      }

      if (durationMinutes <= 0) {
        addAssistantMessage(
          "Dis-moi simplement la durée du rendez-vous, par exemple 30 min, 1h ou 1h30 💕",
        );
        return true;
      }

      pendingSlotProposalRequest = {
        ...pending,
        "step": "travelGo",
        "durationMinutes": durationMinutes,
      };

      addAssistantMessage(
        [
          "Très bien 💕",
          "",
          "Combien de temps faut-il prévoir pour le trajet aller ?",
          "Tu peux répondre 0 si aucun trajet.",
        ].join("\n"),
      );

      return true;
    }

    if (step == "travel" || step == "travelGo") {
      final lower = text.trim().toLowerCase();

      final isExplicitNoTravel = PlannerEngineService.isNoTravelAnswer(lower) ||
          lower == "0" ||
          lower == "aucun" ||
          lower == "pas de trajet";

      final travelGoMinutes = isExplicitNoTravel
          ? 0
          : SmartPlanningService.parseTravelMinutes(text);

      if (!isExplicitNoTravel && travelGoMinutes <= 0) {
        addAssistantMessage(
          "Dis-moi simplement le trajet aller, par exemple 15 min, 30 min ou 0 si aucun trajet 💕",
        );
        return true;
      }

      pendingSlotProposalRequest = {
        ...pending,
        "step": "travelBack",
        "travelGoMinutes": travelGoMinutes,
      };

      addAssistantMessage(
        "Et combien de temps faut-il prévoir pour le trajet retour ? "
        "Tu peux répondre pareil, 0, 15 min, 30 min, etc. 💕",
      );

      return true;
    }

    if (step == "travelBack") {
      final lower = text.trim().toLowerCase();

      final durationMinutes =
          int.tryParse(pending["durationMinutes"]?.toString() ?? "0") ?? 0;
      final travelGoMinutes =
          int.tryParse(pending["travelGoMinutes"]?.toString() ?? "0") ?? 0;

      if (durationMinutes <= 0) {
        pendingSlotProposalRequest = {
          ...pending,
          "step": "duration",
        };

        addAssistantMessage(
          "Il me manque la durée du rendez-vous. Combien de temps veux-tu prévoir ?",
        );
        return true;
      }

      final isSameTravel = lower.contains("pareil") ||
          lower.contains("même") ||
          lower.contains("meme") ||
          lower.contains("identique");

      final isExplicitNoTravel = PlannerEngineService.isNoTravelAnswer(lower) ||
          lower == "0" ||
          lower == "aucun" ||
          lower == "pas de trajet";

      final travelBackMinutes = isSameTravel
          ? travelGoMinutes
          : isExplicitNoTravel
              ? 0
              : SmartPlanningService.parseTravelMinutes(text);

      if (!isSameTravel && !isExplicitNoTravel && travelBackMinutes <= 0) {
        addAssistantMessage(
          "Dis-moi simplement le trajet retour, par exemple 15 min, 30 min, pareil ou 0 si aucun trajet 💕",
        );
        return true;
      }

      final lowerOriginal = originalMessage.toLowerCase();

      final isExactDateRequest = lowerOriginal.contains("demain") ||
          lowerOriginal.contains("aujourd'hui") ||
          lowerOriginal.contains("aujourd’hui") ||
          lowerOriginal.contains("ce soir") ||
          lowerOriginal.contains("cet après-midi") ||
          lowerOriginal.contains("cet apres-midi") ||
          lowerOriginal.contains("ce matin");

      final searchDays = isExactDateRequest
          ? 1
          : lowerOriginal.contains("semaine prochaine")
              ? 7
              : 21;

      final task = TaskModel(
        title: title,
        category: "Agenda",
        isDone: false,
        createdAt: DateTime.now(),
        dueDate: SmartPlanningService.formatIsoDate(startDate),
        planning: SmartPlanningService.formatIsoDate(startDate),
        notes: originalMessage,
      );

      final type = SmartPlanningService.detectTaskType(
        originalMessage,
        task,
      );

      final marginMinutes = SmartPlanningService.defaultMarginMinutes(type);

      final totalMinutes =
          durationMinutes + travelGoMinutes + travelBackMinutes + marginMinutes;

      final result = await PlanningProposalEngine.findBestOptions(
        startDate: startDate,
        totalMinutes: totalMinutes,
        reasoning: await buildCurrentPlanningReasoning(),
        searchDays: searchDays,
        maxOptions: 3,
      );

      pendingSlotProposalRequest = null;

      if (!result.hasOptions || result.options.isEmpty) {
        addAssistantMessage(
          [
            "Je n’ai pas trouvé de créneau disponible réaliste pour « $title » sur cette période 💕",
            "",
            "Tu veux que je cherche plus loin ?",
          ].join("\n"),
        );
        return true;
      }

      pendingPlanningProposalOptions = result.options;
      pendingPlanningProposalContext = {
        "task": task,
        "originalMessage": originalMessage,
        "actionMinutes": durationMinutes,
        "travelGoMinutes": travelGoMinutes,
        "travelBackMinutes": travelBackMinutes,
        "marginMinutes": marginMinutes,
        "groupedTasks": <TaskModel>[task],
      };

      final lines = <String>[
        "Voici les créneaux disponibles que je peux te proposer pour « $title » 💕",
        "",
      ];

      for (var index = 0; index < result.options.length; index++) {
        final option = result.options[index];
        lines.add("${index + 1}. ${option.label}");
      }

      lines.add("");
      lines.add("Réponds 1, 2 ou 3 pour choisir le créneau.");

      addAssistantMessage(lines.join("\n"));
      return true;
    }

    return false;
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
      selectedMinutes = ChatPlanningHelperService.parseDurationMinutes(text);

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

    final showedMultiSlotProposal = await tryShowMultiSlotProposal(
      task: task,
      originalMessage: originalMessage,
      actionMinutes: selectedMinutes,
      travelGoMinutes: 0,
      travelBackMinutes: 0,
      groupedTasks: groupedTasks,
    );

    if (showedMultiSlotProposal) {
      return true;
    }

    final proposal = await PlanningProposalService.buildFromDurationPlanning(
      task: task,
      originalMessage: originalMessage,
      actionMinutes: selectedMinutes,
      memoryReasoning: await buildCurrentMemoryReasoning(),
    );

    if (!proposal.canPropose) {
      pendingAlternativePlanningTask = {
        "task": task,
        "originalMessage": originalMessage,
        "actionMinutes": selectedMinutes,
        "travelGoMinutes": 0,
        "groupedTasks": groupedTasks,
        "failedDate": proposal.date,
      };

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

    final step = pending["step"]?.toString() ?? "travelGo";
    final lower = text.trim().toLowerCase();

    if (step == "travelGo") {
      final isExplicitNoTravel = PlannerEngineService.isNoTravelAnswer(lower) ||
          lower == "0" ||
          lower == "aucun" ||
          lower == "pas de trajet";

      final travelGoMinutes = isExplicitNoTravel
          ? 0
          : SmartPlanningService.parseTravelMinutes(text);

      if (!isExplicitNoTravel && travelGoMinutes <= 0) {
        addAssistantMessage(
          SmartPlanningResponseBuilder.askTravelDurationExample(),
        );
        return true;
      }

      pendingTravelPlanningTask = {
        ...pending,
        "step": "travelBack",
        "travelGoMinutes": travelGoMinutes,
      };

      addAssistantMessage(
        SmartPlanningResponseBuilder.askTravelBackForOutsideTask(),
      );

      return true;
    }

    if (step != "travelBack") {
      pendingTravelPlanningTask = null;
      return false;
    }

    final travelGoMinutes =
        int.tryParse(pending["travelGoMinutes"]?.toString() ?? "0") ?? 0;

    final isSameTravel = lower.contains("pareil") ||
        lower.contains("même") ||
        lower.contains("meme") ||
        lower.contains("identique");

    final isExplicitNoTravel = PlannerEngineService.isNoTravelAnswer(lower) ||
        lower == "0" ||
        lower == "aucun" ||
        lower == "pas de trajet";

    final travelBackMinutes = isSameTravel
        ? travelGoMinutes
        : isExplicitNoTravel
            ? 0
            : SmartPlanningService.parseTravelMinutes(text);

    if (!isSameTravel && !isExplicitNoTravel && travelBackMinutes <= 0) {
      addAssistantMessage(
        SmartPlanningResponseBuilder.askTravelBackDurationExample(),
      );
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

    final showedMultiSlotProposal = await tryShowMultiSlotProposal(
      task: task,
      originalMessage: originalMessage,
      actionMinutes: actionMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      groupedTasks: groupedTasks,
    );

    if (showedMultiSlotProposal) {
      return true;
    }

    final proposal = await PlanningProposalService.buildFromTravelPlanning(
      task: task,
      originalMessage: originalMessage,
      actionMinutes: actionMinutes,
      travelGoMinutes: travelGoMinutes,
      travelBackMinutes: travelBackMinutes,
      groupedTasks: groupedTasks,
      memoryReasoning: await buildCurrentMemoryReasoning(),
    );

    if (!proposal.canPropose) {
      pendingAlternativePlanningTask = {
        "task": task,
        "originalMessage": originalMessage,
        "actionMinutes": actionMinutes,
        "travelGoMinutes": travelGoMinutes,
        "travelBackMinutes": travelBackMinutes,
        "groupedTasks": groupedTasks,
        "failedDate": proposal.date,
      };

      addAssistantMessage(proposal.confirmationMessage);
      return true;
    }

    pendingSmartPlanningProposal = proposal;
    addAssistantMessage(proposal.confirmationMessage);
    return true;
  }

  Future<bool> tryCompletePendingEventConfirmation(
    String text,
  ) async {
    final event = pendingConfirmationEvent;

    if (event == null) return false;

    if (PlannerEngineService.isNegativeAnswer(text)) {
      pendingConfirmationEvent = null;

      addAssistantMessage(
        EventConfirmationService.buildCancellationMessage(event),
      );

      return true;
    }

    if (!PlannerEngineService.isPositiveAnswer(text)) {
      addAssistantMessage(
        EventConfirmationService.buildExpectedAnswerMessage(),
      );

      return true;
    }

    final result = await EventConfirmationService.confirm(
      event: event,
      conflictChecker: EventService.getOverlapConflict,
      addEvent: EventService.addEvent,
      addEvents: EventService.addEvents,
      showNotification: NotificationService.showNotification,
    );

    pendingConfirmationEvent = null;
    addAssistantMessage(result.message);

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

    final time = ChatPlanningHelperService.normalizeTime(text);

    if (time.isEmpty) {
      addAssistantMessage(
        ConflictEngineService.askNewTimeMessage(),
      );
      return true;
    }

    final action = ConflictEngineService.buildRescheduledAction(
      pendingAction: pendingConflictResolutionEvent!,
      time: time,
    );

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
      pendingDateEvent = null;

      final title = action["title"]?.toString() ?? "Rendez-vous";
      final category = action["category"]?.toString() ?? "Personnel";

      final task = TaskModel(
        title: title,
        category: category.trim().isNotEmpty ? category : "Personnel",
        isDone: false,
        createdAt: DateTime.now(),
        dueDate: "",
        planning: "Cette semaine",
      );

      pendingDurationPlanningTask = {
        "task": task,
        "originalMessage": "$title cette semaine",
        "type": action["type"]?.toString() ?? "rendez-vous",
        "outside": true,
        "estimatedMinutes": 0,
        "groupedTasks": <TaskModel>[],
        "planningDraft": {
          "sourceMessage": "$title cette semaine",
          "title": title,
          "type": action["type"]?.toString() ?? "event",
          "category": category,
          "dateIso": "",
          "periodLabel": "Cette semaine",
          "time": "",
          "durationMinutes": 0,
          "needsDate": false,
          "needsTime": true,
          "needsDuration": true,
          "needsTravel": true,
          "needsConfirmation": true,
          "status": "draft",
          "source": "unknown_date_external_event_flow",
        },
      };

      addAssistantMessage(
        "D’accord, je garde ce rendez-vous à organiser cette semaine.\n\n"
        "Combien de temps veux-tu prévoir pour ce rendez-vous ?",
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

      final rawDraft = action["planningDraft"];

      final draft = rawDraft is Map<String, dynamic>
          ? PlanningDraftModel.fromJson(rawDraft)
          : PlanningDraftService.buildFromAction(
              action: action,
              sourceMessage: action["originalUserMessage"]?.toString() ??
                  currentUserMessage,
              needsTravel: eventNeedsTravel(action),
            );

      pendingDurationPlanningTask =
          PlanningDraftService.toPendingDurationPlanningTask(draft);

      final title = draft.title.isNotEmpty ? draft.title : "ce rendez-vous";

      addAssistantMessage(
        "D’accord, je vais te proposer un créneau disponible pour « $title ».\n\n"
        "Combien de temps veux-tu prévoir pour ce rendez-vous ?",
      );

      return true;
    }

    final time = ChatPlanningHelperService.normalizeTime(text);

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
    final pending = pendingTravelEvent;

    if (pending == null) return false;

    final action = Map<String, dynamic>.from(pending);
    final step = action["travelStep"]?.toString() ?? "travelGo";
    final lower = text.trim().toLowerCase();

    if (step == "travelGo") {
      final isExplicitNoTravel = PlannerEngineService.isNoTravelAnswer(lower) ||
          lower == "0" ||
          lower == "aucun" ||
          lower == "pas de trajet";

      final travelGoMinutes = isExplicitNoTravel
          ? 0
          : SmartPlanningService.parseTravelMinutes(text);

      if (!isExplicitNoTravel && travelGoMinutes <= 0) {
        addAssistantMessage(
          "Dis-moi juste le temps du trajet aller, par exemple 10 min, "
          "15 min, 25 min ou 0 si aucun trajet 💕",
        );
        return true;
      }

      action["travelStep"] = "travelBack";
      action["travelGoMinutes"] = travelGoMinutes;
      pendingTravelEvent = action;

      addAssistantMessage(
        "Et combien de temps faut-il prévoir pour le trajet retour ? "
        "Tu peux répondre pareil, 0, 15 min, 30 min, etc. 💕",
      );

      return true;
    }

    if (step != "travelBack") {
      pendingTravelEvent = null;
      return false;
    }

    final travelGoMinutes =
        int.tryParse(action["travelGoMinutes"]?.toString() ?? "0") ?? 0;

    final isSameTravel = lower.contains("pareil") ||
        lower.contains("même") ||
        lower.contains("meme") ||
        lower.contains("identique");

    final isExplicitNoTravel = PlannerEngineService.isNoTravelAnswer(lower) ||
        lower == "0" ||
        lower == "aucun" ||
        lower == "pas de trajet";

    final travelBackMinutes = isSameTravel
        ? travelGoMinutes
        : isExplicitNoTravel
            ? 0
            : SmartPlanningService.parseTravelMinutes(text);

    if (!isSameTravel && !isExplicitNoTravel && travelBackMinutes <= 0) {
      addAssistantMessage(
        "Dis-moi juste le temps du trajet retour, par exemple 10 min, "
        "15 min, pareil ou 0 si aucun trajet 💕",
      );
      return true;
    }

    action.remove("travelStep");
    action["travelGoMinutes"] = travelGoMinutes;
    action["travelBackMinutes"] = travelBackMinutes;
    action["travelMinutes"] = travelGoMinutes + travelBackMinutes;

    pendingTravelEvent = null;

    final conflictText = await handleAction(action);
    final title = action["title"]?.toString() ?? "ce rendez-vous";

    final reply = conflictText.isNotEmpty
        ? conflictText
        : "C’est noté 💕 J’ai bloqué « $title » dans ton agenda, "
            "avec $travelGoMinutes min de trajet aller et "
            "$travelBackMinutes min de trajet retour.";

    addAssistantMessage(reply);
    return true;
  }

  Future<bool> tryCompletePendingDuration(String text) async {
    if (pendingDurationEvent == null) return false;

    final duration = ChatPlanningHelperService.parseDurationMinutes(text);

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
      final completedEventConfirmation =
          await tryCompletePendingEventConfirmation(text);
      if (completedEventConfirmation) return;

      final completedConflictResolution =
          await tryCompletePendingConflictResolution(text);
      if (completedConflictResolution) return;

      final completedSlotProposalRequest =
          await tryCompletePendingSlotProposalRequest(text);
      if (completedSlotProposalRequest) return;

      final completedSelectedSlotEvent =
          await tryCompletePendingSelectedSlotEvent(text);
      if (completedSelectedSlotEvent) return;

      final completedPlanningSelection =
          await tryCompletePlanningProposalSelection(text);
      if (completedPlanningSelection) return;

      final completedDateEvent = await tryCompletePendingDateEvent(text);
      if (completedDateEvent) return;

      final completedTimeEvent = await tryCompletePendingTimeEvent(text);
      if (completedTimeEvent) return;

      final completedAlternativePlanning =
          await tryCompletePendingAlternativePlanning(text);

      if (completedAlternativePlanning) return;

      final completedSmartPlanning =
          await tryCompletePendingSmartPlanning(text);

      if (completedSmartPlanning) return;

      final startedSlotProposal = await tryStartSlotProposalRequest(text);
      if (startedSlotProposal) return;

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

        final payload = MemoryPipelineService.buildSavePayload(
          memory,
          fallbackText: text,
        );

        await MemoryService.saveMemory(
          text: payload.text,
          category: payload.category,
          importance: payload.importance,
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

      final profileContext =
          ProfileContextBuilderService.buildStructuredContext(widget.profile);

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
          "profileContext": profileContext,
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
        for (final rawAction in actions) {
          final guarded = ZeliaActionGuardService.guard(rawAction);

          if (!guarded.isAccepted || guarded.action == null) {
            continue;
          }

          final action = guarded.action!;
          final type = action["type"]?.toString() ?? "";
          final title = action["title"]?.toString() ?? "";

          if (type == "shopping" && title.isNotEmpty) {
            shoppingTitles.add(title);
          }

          if (type == "task" && title.isNotEmpty) {
            taskTitles.add(title);
          }

          if (type == "event" && title.isNotEmpty) {
            eventTitles.add(title);
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

    final payload = MemoryPipelineService.buildSavePayload(
      builtMemory,
      fallbackText: text,
    );

    await MemoryService.saveMemory(
      text: payload.text,
      category: payload.category,
      importance: payload.importance,
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
      normalizeTime: ChatPlanningHelperService.normalizeTime,
      parseDurationMinutes: ChatPlanningHelperService.parseDurationMinutes,
      weekdayFromText: weekdayFromText,
      messageLooksRecurringWeekly: messageLooksRecurringWeekly,
      nextDateForWeekday: nextDateForWeekday,
      eventNeedsTravel: eventNeedsTravel,
      buildStartDateTimeIso: ChatPlanningHelperService.buildStartDateTimeIso,
      buildEndDateTimeIso: ChatPlanningHelperService.buildEndDateTimeIso,
      endTimeFromDuration: ChatPlanningHelperService.endTimeFromDuration,
    );

    if (result.pendingDateEvent != null) {
      pendingDateEvent = result.pendingDateEvent;
    }

    if (result.pendingTimeEvent != null) {
      final pendingAction = Map<String, dynamic>.from(
        result.pendingTimeEvent!,
      );

      final draft = PlanningDraftService.buildFromAction(
        action: pendingAction,
        sourceMessage: currentUserMessage,
        needsTravel: eventNeedsTravel(pendingAction),
      );

      pendingTimeEvent = PlanningDraftService.toPendingTimeEvent(draft);
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

    if (result.pendingConfirmationEvent != null) {
      pendingConfirmationEvent = result.pendingConfirmationEvent;
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
