import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/screens/home_screen.dart';
import 'package:moms_ai/screens/main_navigation.dart';
import 'package:moms_ai/services/dashboard_anticipation_service.dart';

void main() {
  test('la pensée Dashboard reste ouvrable quand sa destination est le chat',
      () {
    const anticipation = DashboardAnticipation(
      title: 'À anticiper',
      message: 'Un sujet mérite ton attention.',
      destination: DashboardAnticipationDestination.chat,
      preparedChatMessage: 'On s’en occupe maintenant ou plus tard ?',
    );

    expect(isDashboardAnticipationLinkEnabled(anticipation), isTrue);
    expect(isDashboardAnticipationLinkEnabled(null), isFalse);
  });

  test('le choix Maintenant ouvre une discussion sans demander de mutation',
      () {
    const anticipation = DashboardAnticipation(
      title: 'À anticiper',
      message: 'Préparer les affaires pour le voyage.',
      destination: DashboardAnticipationDestination.chat,
      preparedChatMessage: 'Le voyage approche. Préparons les affaires.',
    );

    final replies = buildDashboardAnticipationQuickReplies(anticipation);
    final now = replies.singleWhere((reply) => reply.id == 'dashboard-now');

    expect(now.visibleText, 'Maintenant');
    expect(now.discussionOnly, isTrue);
    expect(now.submission, contains('Le voyage approche'));
    expect(now.submission, contains('aide concrète'));
    expect(now.submission, contains('aucune action'));
    expect(now.submission, isNot(contains('confirmer')));
  });
}
