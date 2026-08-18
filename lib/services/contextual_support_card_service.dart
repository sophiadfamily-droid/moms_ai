enum ContextualSupportSurface { tasks, shopping }

final class ContextualSupportCardMessage {
  const ContextualSupportCardMessage({
    required this.title,
    required this.message,
    required this.semanticKey,
  });

  final String title;
  final String message;
  final String semanticKey;
}

/// A small, controlled part of the user's communication style that can be
/// learned from repeated conversations. Personal facts never belong here.
final class ContextualCommunicationStyle {
  const ContextualCommunicationStyle({this.familiarEncouragement});

  /// A short, harmless expression the user regularly employs (for example
  /// “C’est carré”). The upstream learning layer must only provide it after
  /// repeated evidence or an explicit user choice.
  final String? familiarEncouragement;
}

/// Builds the compact support message shown when no stronger actionable
/// suggestion is available. Copy is based only on facts loaded by the screen.
final class ContextualSupportCardService {
  const ContextualSupportCardService();

  ContextualSupportCardMessage forTasks({
    required int openCount,
    required int completedCount,
    required DateTime now,
    ContextualCommunicationStyle style = const ContextualCommunicationStyle(),
  }) {
    final open = openCount < 0 ? 0 : openCount;
    final completed = completedCount < 0 ? 0 : completedCount;

    if (open == 0 && completed == 0) {
      return _pick(
        surface: ContextualSupportSurface.tasks,
        now: now,
        fingerprint: 'empty',
        messages: const [
          ContextualSupportCardMessage(
            title: 'Un peu d’air',
            message: 'Rien à gérer dans cette liste.',
            semanticKey: 'tasks_empty_breathe',
          ),
          ContextualSupportCardMessage(
            title: 'C’est calme ici',
            message: 'Garde ce moment pour toi.',
            semanticKey: 'tasks_empty_clear',
          ),
          ContextualSupportCardMessage(
            title: 'La liste est libre',
            message: 'Tu peux penser à autre chose.',
            semanticKey: 'tasks_empty_space',
          ),
        ],
      );
    }

    if (open == 0) {
      return _pick(
        surface: ContextualSupportSurface.tasks,
        now: now,
        fingerprint: 'done:$completed',
        messages: [
          ContextualSupportCardMessage(
            title: _positiveTitle('C’est fait', style),
            message: 'Ta liste est à jour.',
            semanticKey: 'tasks_all_done_progress',
          ),
          ContextualSupportCardMessage(
            title: _positiveTitle('Tu peux souffler', style),
            message: 'Tout est coché ici.',
            semanticKey: 'tasks_all_done_pause',
          ),
          ContextualSupportCardMessage(
            title: _positiveTitle('Belle avancée', style),
            message: 'Tu as bouclé ta liste.',
            semanticKey: 'tasks_all_done_clear',
          ),
        ],
      );
    }

    if (completed > 0) {
      return _pick(
        surface: ContextualSupportSurface.tasks,
        now: now,
        fingerprint: 'mixed:$open:$completed',
        messages: [
          ContextualSupportCardMessage(
            title: _positiveTitle('Bien avancé', style),
            message: 'Tu as déjà avancé. Le reste peut attendre son tour.',
            semanticKey: 'tasks_mixed_progress',
          ),
          ContextualSupportCardMessage(
            title: _positiveTitle('Ça avance', style),
            message: 'Continue à ton rythme.',
            semanticKey: 'tasks_mixed_step',
          ),
          ContextualSupportCardMessage(
            title: _positiveTitle('Petit à petit', style),
            message: 'Une partie est déjà derrière toi.',
            semanticKey: 'tasks_mixed_momentum',
          ),
        ],
      );
    }

    return _pick(
      surface: ContextualSupportSurface.tasks,
      now: now,
      fingerprint: 'open:$open',
      messages: [
        ContextualSupportCardMessage(
          title: 'À ton rythme',
          message: 'Une seule chose à la fois.',
          semanticKey: 'tasks_open_paced',
        ),
        ContextualSupportCardMessage(
          title: 'C’est noté',
          message: 'Prends la prochaine quand tu veux.',
          semanticKey: 'tasks_open_step',
        ),
        ContextualSupportCardMessage(
          title: 'Je garde le fil',
          message: 'Tes tâches sont là quand tu es prête.',
          semanticKey: 'tasks_open_noted',
        ),
      ],
    );
  }

  ContextualSupportCardMessage forShopping({
    required int pendingCount,
    required int boughtCount,
    required int urgentCount,
    required DateTime now,
    ContextualCommunicationStyle style = const ContextualCommunicationStyle(),
  }) {
    final pending = pendingCount < 0 ? 0 : pendingCount;
    final bought = boughtCount < 0 ? 0 : boughtCount;
    final urgent = urgentCount < 0 ? 0 : urgentCount;

    if (urgent > 0) {
      return ContextualSupportCardMessage(
        title: 'À ne pas oublier',
        message: urgent == 1
            ? 'Un produit est urgent dans ta liste.'
            : '$urgent produits sont urgents dans ta liste.',
        semanticKey: 'shopping_urgent',
      );
    }

    if (pending == 0 && bought == 0) {
      return _pick(
        surface: ContextualSupportSurface.shopping,
        now: now,
        fingerprint: 'empty',
        messages: const [
          ContextualSupportCardMessage(
            title: 'Liste libre',
            message: 'Ajoute ce qui te vient, quand tu veux.',
            semanticKey: 'shopping_empty_light',
          ),
          ContextualSupportCardMessage(
            title: 'Je suis prête',
            message: 'Dis-moi dès qu’un produit te revient.',
            semanticKey: 'shopping_empty_memory',
          ),
          ContextualSupportCardMessage(
            title: 'C’est calme ici',
            message: 'Rien à acheter dans cette liste.',
            semanticKey: 'shopping_empty_calm',
          ),
        ],
      );
    }

    if (pending == 0) {
      return _pick(
        surface: ContextualSupportSurface.shopping,
        now: now,
        fingerprint: 'bought:$bought',
        messages: [
          ContextualSupportCardMessage(
            title: _positiveTitle('C’est fait', style),
            message: 'Tout est coché.',
            semanticKey: 'shopping_all_bought_done',
          ),
          ContextualSupportCardMessage(
            title: _positiveTitle('Courses à jour', style),
            message: 'Tu peux passer à autre chose.',
            semanticKey: 'shopping_all_bought_clear',
          ),
          ContextualSupportCardMessage(
            title: _positiveTitle('Bien joué', style),
            message: 'La liste est terminée.',
            semanticKey: 'shopping_all_bought_memory',
          ),
        ],
      );
    }

    return _pick(
      surface: ContextualSupportSurface.shopping,
      now: now,
      fingerprint: 'pending:$pending:bought:$bought',
      messages: [
        ContextualSupportCardMessage(
          title: 'C’est noté',
          message: 'Je garde ta liste sous la main.',
          semanticKey: 'shopping_pending_ready',
        ),
        ContextualSupportCardMessage(
          title: 'Pour les courses',
          message: 'Tout est là.',
          semanticKey: 'shopping_pending_noted',
        ),
        ContextualSupportCardMessage(
          title: 'Je m’en souviens',
          message: 'Ta liste est prête.',
          semanticKey: 'shopping_pending_progress',
        ),
      ],
    );
  }

  String _positiveTitle(
    String fallback,
    ContextualCommunicationStyle style,
  ) {
    final familiar = style.familiarEncouragement?.trim();
    if (familiar == null || familiar.length < 2 || familiar.length > 28) {
      return fallback;
    }
    if (familiar.contains('\n') || familiar.contains('\r')) return fallback;
    final safeCharacters = RegExp(
      r"^[A-Za-zÀ-ÖØ-öø-ÿŒœ'’!?., -]+$",
    );
    return safeCharacters.hasMatch(familiar) ? familiar : fallback;
  }

  ContextualSupportCardMessage _pick({
    required ContextualSupportSurface surface,
    required DateTime now,
    required String fingerprint,
    required List<ContextualSupportCardMessage> messages,
  }) {
    if (messages.length == 1) return messages.single;
    final day = DateTime(now.year, now.month, now.day)
        .difference(DateTime(2020))
        .inDays;
    final seed = '${surface.name}:$fingerprint';
    final checksum = seed.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return messages[(day + checksum) % messages.length];
  }
}
