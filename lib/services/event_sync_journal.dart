import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event_sync_models.dart';

final class EventSyncJournal {
  static const String storageKey = 'zelia_event_sync_journal_v1';
  static const int maxOperations = 500;

  Future<List<PendingEventSyncOperation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(storageKey) ?? const [];
    final operations = <PendingEventSyncOperation>[];
    final ids = <String>{};
    for (final item in raw) {
      final decoded = jsonDecode(item);
      if (decoded is! Map) {
        throw const FormatException('invalid_event_sync_journal');
      }
      final operation = PendingEventSyncOperation.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (!ids.add(operation.operationId)) {
        throw const FormatException('duplicate_event_sync_operation');
      }
      operations.add(operation);
    }
    operations.sort((a, b) {
      final date = a.createdAt.compareTo(b.createdAt);
      return date != 0 ? date : a.operationId.compareTo(b.operationId);
    });
    return operations;
  }

  Future<void> save(List<PendingEventSyncOperation> operations) async {
    final retained = operations.where((operation) => !operation.isTerminal);
    if (retained.length > maxOperations) {
      throw const FormatException('event_sync_journal_limit_reached');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey,
      retained.map((operation) => jsonEncode(operation.toJson())).toList(),
    );
  }

  Future<void> append(PendingEventSyncOperation operation) async {
    final operations = await load();
    if (operations.any((item) => item.operationId == operation.operationId)) {
      return;
    }
    await save([...operations, operation]);
  }
}
