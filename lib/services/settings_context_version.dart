import 'package:flutter/foundation.dart';

/// Invalidates the read-only settings section of Life Context after a
/// specialized settings owner persists a change.
abstract final class SettingsContextVersion {
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void notifyChanged() => changes.value++;
}
