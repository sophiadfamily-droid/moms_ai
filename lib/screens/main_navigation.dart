import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../models/agenda_focus.dart';
import '../models/agenda_conflict_help.dart';
import '../models/priority/proactive_priority_models.dart';
import '../services/conversation_session_controller.dart';
import '../services/agenda_conflict_suggestion_service.dart';
import '../services/identity/identity_production_services.dart';
import '../services/priority/proactive_interaction_registry.dart';

import 'home_screen.dart';
import 'chat_screen.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';
import 'shopping_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  final UserProfile profile;
  final ValueChanged<UserProfile>? onProfileUpdated;
  final Widget Function(
    UserProfile profile,
    ValueChanged<UserProfile> onSave,
  )? profileScreenBuilder;
  final List<Widget>? testScreens;
  final IdentityProductionServices? identityServices;
  final ProactiveInteractionRegistry? proactiveInteractionRegistry;
  final String? accountScopeId;

  const MainNavigation({
    super.key,
    required this.profile,
    this.onProfileUpdated,
    this.profileScreenBuilder,
    this.testScreens,
    this.identityServices,
    this.proactiveInteractionRegistry,
    this.accountScopeId,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int currentIndex = 0;
  AgendaFocus? requestedAgendaFocus;
  bool _isFindingConflictSolution = false;

  late UserProfile currentProfile;

  late final ProactiveInteractionRegistry _proactiveInteractionRegistry;
  ConversationSessionController? _conversationSessionController;

  @override
  void initState() {
    super.initState();
    currentProfile = widget.profile;
    _proactiveInteractionRegistry = widget.proactiveInteractionRegistry ??
        ProactiveInteractionRegistry.instance;
    if (widget.testScreens == null) {
      _conversationSessionController = ConversationSessionController.production(
        profile: currentProfile,
        identityServices: widget.identityServices,
        proactiveInteractionRegistry: _proactiveInteractionRegistry,
      );
    }
  }

  @override
  void didUpdateWidget(
    covariant MainNavigation oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profile != widget.profile) {
      currentProfile = widget.profile;
    }
  }

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  void openAgenda(AgendaFocus focus) {
    setState(() {
      requestedAgendaFocus = focus;
      currentIndex = 2;
    });
  }

  void openChatWithSuggestion(ProactiveTaskDurationHandoff handoff) {
    _conversationSessionController!.beginProactiveTaskDuration(
      handoff: handoff,
    );
    setState(() {
      currentIndex = 1;
    });
  }

  Future<void> openConflictHelp(AgendaConflictHelp help) async {
    if (_isFindingConflictSolution) return;
    _isFindingConflictSolution = true;
    _conversationSessionController!.addInitialAssistantMessage(
      'Je regarde où je peux déplacer « ${help.eventTitle} » sans créer '
      'un autre problème.',
    );
    setState(() => currentIndex = 1);
    try {
      final suggestion = await AgendaConflictSuggestionService().suggest(
        accountScopeId: widget.accountScopeId ?? 'guest',
        eventId: help.eventId,
      );
      if (!mounted) return;
      if (suggestion == null) {
        _conversationSessionController!.addInitialAssistantMessage(
          'Je n’ai pas trouvé de créneau assez sûr pour le moment. '
          'Je n’ai rien modifié.',
        );
        return;
      }
      await _conversationSessionController!.beginProactiveEventMove(suggestion);
    } catch (_) {
      if (!mounted) return;
      _conversationSessionController!.addInitialAssistantMessage(
        'Je n’arrive pas à vérifier ton agenda pour le moment. '
        'Je n’ai rien modifié.',
      );
    } finally {
      _isFindingConflictSolution = false;
    }
  }

  void updateProfile(UserProfile updatedProfile) {
    setState(() {
      currentProfile = updatedProfile;
    });

    widget.onProfileUpdated?.call(updatedProfile);
    _conversationSessionController?.changeAccount(updatedProfile);
  }

  @override
  void dispose() {
    _conversationSessionController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = widget.testScreens ??
        [
          HomeScreen(
            profile: currentProfile,
            onNavigate: changeTab,
            onOpenAgenda: openAgenda,
          ),
          ChatScreen(
            profile: currentProfile,
            identityServices: widget.identityServices,
            sessionController: _conversationSessionController!,
            proactiveInteractionRegistry: _proactiveInteractionRegistry,
          ),
          CalendarScreen(
            key: ValueKey(
              'calendar:${widget.accountScopeId ?? 'guest'}:'
              '${requestedAgendaFocus?.date?.toUtc().toIso8601String() ?? 'today'}:'
              '${requestedAgendaFocus?.eventId ?? ''}:'
              '${requestedAgendaFocus?.routineId ?? ''}',
            ),
            accountScopeToken: widget.accountScopeId ?? 'guest',
            initialDate: requestedAgendaFocus?.date,
            highlightedEventId: requestedAgendaFocus?.eventId,
            highlightedRoutineId: requestedAgendaFocus?.routineId,
            highlightedEventTitle: requestedAgendaFocus?.eventTitle,
            highlightedRoutineTitle: requestedAgendaFocus?.routineTitle,
            onAskZeliaForConflict: openConflictHelp,
          ),
          TasksScreen(
            onOpenZeliaSuggestion: openChatWithSuggestion,
            onNavigate: changeTab,
            isDashboardActive: currentIndex == 3,
            proactiveInteractionRegistry: _proactiveInteractionRegistry,
          ),
          const ShoppingScreen(),
          widget.profileScreenBuilder?.call(
                currentProfile,
                updateProfile,
              ) ??
              ProfileScreen(
                profile: currentProfile,
                onSave: updateProfile,
              ),
        ];

    assert(
      screens.length == 6,
      'MainNavigation requires exactly 6 screens.',
    );

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9F2F8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 86,
            backgroundColor: const Color(0xFFF9F2F8),
            indicatorColor: const Color(0xFFE8D9FF),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
              (states) {
                final selected = states.contains(WidgetState.selected);

                return TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? const Color(0xFF2D2730)
                      : const Color(0xFF6E6570),
                );
              },
            ),
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
              (states) {
                final selected = states.contains(WidgetState.selected);

                return IconThemeData(
                  size: selected ? 28 : 26,
                  color: selected
                      ? const Color(0xFF3B3440)
                      : const Color(0xFF5F5964),
                );
              },
            ),
          ),
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: changeTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(CupertinoIcons.house),
                selectedIcon: Icon(CupertinoIcons.house_fill),
                label: "Accueil",
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.sparkles),
                selectedIcon: Icon(CupertinoIcons.sparkles),
                label: "Zelia",
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.calendar),
                selectedIcon: Icon(CupertinoIcons.calendar),
                label: "Agenda",
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.checkmark_square),
                selectedIcon: Icon(CupertinoIcons.checkmark_square_fill),
                label: "Tâches",
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.bag),
                selectedIcon: Icon(CupertinoIcons.bag_fill),
                label: "Courses",
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.person),
                selectedIcon: Icon(CupertinoIcons.person_fill),
                label: "Profil",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
