abstract final class EntityIdentity {
  static bool isValid(String? id) {
    return id != null && id.trim().isNotEmpty;
  }
}
