import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';

import 'home_screen.dart';
import 'chat_screen.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';
import 'shopping_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  final UserProfile profile;
  final ValueChanged<UserProfile>? onProfileUpdated;

  const MainNavigation({
    super.key,
    required this.profile,
    this.onProfileUpdated,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int currentIndex = 0;

  late UserProfile currentProfile;

  String? zeliaSuggestionMessage;

  @override
  void initState() {
    super.initState();
    currentProfile = widget.profile;
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

  void openChatWithSuggestion(String message) {
    setState(() {
      zeliaSuggestionMessage = message;
      currentIndex = 1;
    });
  }

  void updateProfile(UserProfile updatedProfile) {
    setState(() {
      currentProfile = updatedProfile;
    });

    widget.onProfileUpdated?.call(updatedProfile);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(
        profile: currentProfile,
        onNavigate: changeTab,
      ),
      ChatScreen(
        profile: currentProfile,
        initialAssistantMessage: zeliaSuggestionMessage,
      ),
      const CalendarScreen(),
      TasksScreen(
        onOpenZeliaSuggestion: openChatWithSuggestion,
      ),
      const ShoppingScreen(),
      ProfileScreen(
        profile: currentProfile,
        onSave: updateProfile,
      ),
    ];

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
              color: Colors.black.withOpacity(0.04),
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
