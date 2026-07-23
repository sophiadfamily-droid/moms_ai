import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event_sync_models.dart';

final class EventSyncJournal {
  static const String storageKey = 'zelia_event_sync_journal_v1';
  static const String receiptStorageKey =
      'zelia_event_sync_journal_receipts_v1';
  static const int maxOperations = 500;
  static const int maxResolutionReceipts = 100;

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
    final active = operations.where(
      (operation) =>
          operation.state != EventSyncOperationState.applied &&
          operation.state != EventSyncOperationState.cancelled,
    );
    final receipts = operations
        .where((operation) =>
            operation.state == EventSyncOperationState.applied ||
            operation.state == EventSyncOperationState.cancelled)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final retained = active.toList(growable: false);
    if (retained.length > maxOperations) {
      throw const FormatException('event_sync_journal_limit_reached');
    }
    final receiptById = {
      for (final receipt in await loadReceipts()) receipt.operationId: receipt,
      for (final receipt in receipts) receipt.operationId: receipt,
    };
    final retainedReceipts = receiptById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      receiptStorageKey,
      retainedReceipts
          .take(maxResolutionReceipts)
          .map((operation) => jsonEncode(operation.toJson()))
          .toList(),
    );
    await prefs.setStringList(
      storageKey,
      retained.map((operation) => jsonEncode(operation.toJson())).toList(),
    );
  }

  Future<List<PendingEventSyncOperation>> loadReceipts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(receiptStorageKey) ?? const [];
    if (raw.length > maxResolutionReceipts) {
      throw const FormatException('event_sync_receipt_limit');
    }
    return raw.map((item) {
      final decoded = jsonDecode(item);
      if (decoded is! Map) {
        throw const FormatException('invalid_event_sync_receipt');
      }
      final operation = PendingEventSyncOperation.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (operation.state != EventSyncOperationState.applied &&
          operation.state != EventSyncOperationState.cancelled &&
          operation.state != EventSyncOperationState.resolved &&
          operation.state != EventSyncOperationState.discarded) {
        throw const FormatException('invalid_event_sync_receipt_state');
      }
      return operation;
    }).toList(growable: false);
  }

  Future<void> append(PendingEventSyncOperation operation) async {
    final operations = await load();
    if (operations.any((item) => item.operationId == operation.operationId)) {
      return;
    }
    await save([...operations, operation]);
  }

  Future<void> replace(PendingEventSyncOperation operation) async {
    final operations = await load();
    final index = operations.indexWhere(
      (item) => item.operationId == operation.operationId,
    );
    if (index < 0) throw const FormatException('event_sync_operation_missing');
    operations[index] = operation;
    await save(operations);
  }
}
