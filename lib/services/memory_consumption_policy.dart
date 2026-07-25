import '../models/life_context/memory_context.dart';
import '../models/memory_lifecycle_state.dart';

/// Single read boundary for memories allowed to influence chat or planning.
final class MemoryConsumptionPolicy {
  const MemoryConsumptionPolicy._();

  static Iterable<LifeMemoryFact> consumable(
    Iterable<LifeMemoryFact> memories, {
    required DateTime referenceDate,
  }) =>
      memories.where(
        (memory) => isConsumable(memory, referenceDate: referenceDate),
      );

  static bool isConsumable(
    LifeMemoryFact memory, {
    required DateTime referenceDate,
  }) {
    if (memory.hasRestrictedSecret) return false;
    if (memory.consumptionTrust == MemoryConsumptionTrust.legacyTrusted) {
      final expiration = memory.validUntil;
      return !memory.hasInvalidExpiration &&
          (expiration == null || referenceDate.toUtc().isBefore(expiration));
    }
    if (memory.consumptionTrust != MemoryConsumptionTrust.modernValid) {
      return false;
    }
    if (memory.hasInvalidExpiration ||
        memory.confirmationStatus != MemoryConfirmationStatus.confirmed ||
        !const {
          MemoryLifecycleState.confirmed,
          MemoryLifecycleState.active,
        }.contains(memory.lifecycleState)) {
      return false;
    }
    final expiration = memory.validUntil;
    return expiration == null || referenceDate.toUtc().isBefore(expiration);
  }
}
