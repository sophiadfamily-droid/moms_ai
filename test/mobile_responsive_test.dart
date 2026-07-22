import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/chat_backend_request.dart';
import 'package:moms_ai/models/chat_backend_response.dart';
import 'package:moms_ai/models/user_profile.dart';
import 'package:moms_ai/screens/calendar_screen.dart';
import 'package:moms_ai/screens/chat_screen.dart';
import 'package:moms_ai/screens/main_navigation.dart';
import 'package:moms_ai/screens/profile_screen.dart';
import 'package:moms_ai/screens/shopping_screen.dart';
import 'package:moms_ai/screens/tasks_screen.dart';
import 'package:moms_ai/services/chat_backend_client.dart';
import 'package:moms_ai/services/conversation_context_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sizes = <Size>[
  Size(360, 800),
  Size(390, 844),
  Size(412, 915),
  Size(820, 1180),
  Size(1024, 1366),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in _sizes) {
    testWidgets(
        'main mobile screens remain usable at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final profile = _profile();
      final screens = <Widget>[
        ChatScreen(
          profile: profile,
          backendClient: _Backend(),
          conversationContextProvider: _ContextProvider(),
        ),
        CalendarScreen(
          eventsVersionForTest: ValueNotifier<int>(0),
          loadEventsForTest: () async => [],
        ),
        const TasksScreen(),
        const ShoppingScreen(),
        ProfileScreen(profile: profile),
      ];

      for (final screen in screens) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pump(const Duration(milliseconds: 100));
        _expectNoOverflow(tester);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MainNavigation(
            profile: profile,
            testScreens: List.generate(
              6,
              (index) => Center(child: Text('Écran principal $index')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationDestination), findsNWidgets(6));
      _expectNoOverflow(tester);
    });
  }
}

void _expectNoOverflow(WidgetTester tester) {
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    final description = exception.toString();
    if (description.contains('[core/no-app]')) {
      // ProfileScreen reads the real Auth singleton. Firebase initialization is
      // covered by the device smoke tests; this test owns layout only.
      continue;
    }
    expect(
      description,
      isEmpty,
      reason: 'The tested mobile viewport raised an unexpected UI error.',
    );
  }
}

UserProfile _profile() => UserProfile(
      firstName: 'Test',
      familyStatus: '',
      workStatus: '',
      partnerName: '',
      wantsNotifications: true,
      children: const [],
    );

class _Backend implements ChatBackendClient {
  @override
  Future<ChatBackendResponse> send(ChatBackendRequest request) async {
    return const ChatBackendResponse(
        reply: 'Réponse de test', actions: [], memories: []);
  }
}

class _ContextProvider implements ConversationContextProvider {
  @override
  Future<ChatBackendRequest> buildRequest({
    required String message,
    required UserProfile profile,
  }) async {
    return ChatBackendRequest(
      message: message,
      profile: const {},
      profileContext: const {},
      memories: const [],
      memoryReasoning: const [],
      events: const [],
    );
  }

  @override
  Future<void> saveResponseMemory(dynamic memory) async {}
}
