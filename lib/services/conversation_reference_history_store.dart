import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'conversation_reference_resolver.dart';

abstract interface class ConversationReferenceHistoryStore {
  Future<List<ValidatedConversationReference>> load({
    required String accountScopeId,
    required DateTime referenceDate,
  });

  Future<void> save({
    required String accountScopeId,
    required List<ValidatedConversationReference> references,
    required DateTime referenceDate,
  });
}

final class SharedPreferencesConversationReferenceHistoryStore
    implements ConversationReferenceHistoryStore {
  static const int maximumEntries = 20;
  static const String _keyPrefix = 'conversation_reference_history_v1:';

  const SharedPreferencesConversationReferenceHistoryStore();

  @override
  Future<List<ValidatedConversationReference>> load({
    required String accountScopeId,
    required DateTime referenceDate,
  }) async {
    final scope = accountScopeId.trim();
    if (scope.isEmpty) return const [];
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getStringList('$_keyPrefix$scope') ?? const [];
    final references = <ValidatedConversationReference>[];
    for (final value in encoded.take(maximumEntries)) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is! Map) continue;
        final reference = ValidatedConversationReference.fromPersistedJson(
          Map<String, dynamic>.from(decoded),
          accountScopeId: scope,
        );
        if (reference.isValidAt(referenceDate.toUtc())) {
          references.add(reference);
        }
      } catch (_) {
        // Untrusted local session state is ignored fail-closed.
      }
    }
    await _write(preferences, scope, references);
    return List.unmodifiable(references);
  }

  @override
  Future<void> save({
    required String accountScopeId,
    required List<ValidatedConversationReference> references,
    required DateTime referenceDate,
  }) async {
    final scope = accountScopeId.trim();
    if (scope.isEmpty) return;
    final valid = references
        .where((item) => item.accountScopeId == scope)
        .where((item) => item.isValidAt(referenceDate.toUtc()))
        .take(maximumEntries)
        .toList(growable: false);
    await _write(await SharedPreferences.getInstance(), scope, valid);
  }

  Future<void> _write(
    SharedPreferences preferences,
    String scope,
    List<ValidatedConversationReference> references,
  ) =>
      preferences.setStringList(
        '$_keyPrefix$scope',
        references
            .map((item) => jsonEncode(item.toPersistedJson()))
            .toList(growable: false),
      );
}
