import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'app_diagnostics.dart';
import 'app_error_classifier.dart';

class MemoryService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static final ValueNotifier<int> memoriesVersion = ValueNotifier<int>(0);

  static void notifyMemoriesChanged() {
    memoriesVersion.value++;
  }

  static String normalizeMemoryText(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static CollectionReference<Map<String, dynamic>>? _memoriesRef() {
    final uid = AuthService.currentUserId;

    if (uid == null || uid.isEmpty) {
      return null;
    }

    return firestore.collection("users").doc(uid).collection("memories");
  }

  static Future<bool> memoryAlreadyExists(String text) async {
    final normalizedText = normalizeMemoryText(text);
    if (normalizedText.isEmpty) return true;

    final ref = _memoriesRef();

    if (ref == null) {
      return true;
    }

    try {
      final indexedSnapshot = await ref
          .where("normalizedText", isEqualTo: normalizedText)
          .limit(1)
          .get();

      if (indexedSnapshot.docs.isNotEmpty) return true;

      final legacySnapshot = await ref.get();

      for (final doc in legacySnapshot.docs) {
        final existingText = doc.data()["text"]?.toString() ?? "";
        if (normalizeMemoryText(existingText) == normalizedText) {
          return true;
        }
      }
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'memory',
        domain: 'memory',
        operation: 'deduplicate',
        step: 'duplicate_check',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
      return true;
    }

    return false;
  }

  static Future<void> saveMemory({
    required String text,
    required String category,
    int importance = 0,
  }) async {
    final cleanText = text.trim();
    final normalizedText = normalizeMemoryText(cleanText);

    if (cleanText.isEmpty || normalizedText.isEmpty) return;

    final ref = _memoriesRef();

    if (ref == null) {
      return;
    }

    final exists = await memoryAlreadyExists(cleanText);
    if (exists) return;

    final now = Timestamp.now();

    try {
      await ref.add({
        "text": cleanText,
        "normalizedText": normalizedText,
        "category": category.trim().isEmpty ? "personal" : category.trim(),
        "importance": importance,
        "createdAt": now,
        "updatedAt": now,
        "source": "chat",
      });
      notifyMemoriesChanged();
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'memory',
        domain: 'memory',
        operation: 'save',
        step: 'save',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getMemories() async {
    final ref = _memoriesRef();

    if (ref == null) {
      return [];
    }

    try {
      final snapshot = await ref.orderBy("createdAt", descending: true).get();

      return snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          ...data,
          "id": doc.id,
        };
      }).toList();
    } catch (error) {
      final descriptor = AppErrorClassifier.classify(
        error,
        boundary: AppErrorBoundaryKind.synchronization,
      );
      AppDiagnostics.record(
        component: 'memory',
        domain: 'memory',
        operation: 'load',
        step: 'load',
        code: descriptor.code,
        severity: descriptor.severity,
        retryStrategy: descriptor.retryStrategy,
        correlationId: descriptor.correlationId,
        sourceExceptionType: AppErrorClassifier.safeExceptionType(error),
      );
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getMemoriesForLifeContext(
    String accountScopeId,
  ) async {
    final uid = AuthService.currentUserId;
    if (uid == null || uid.isEmpty || uid != accountScopeId) {
      throw StateError('memory_account_mismatch');
    }
    return getMemories();
  }
}
