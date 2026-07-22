import '../core/identity/entity_identity.dart';
import '../core/identity/entity_types.dart';
import '../core/identity/persisted_identity_link.dart';

enum EventIdentityRole { participant }

final class EventParticipantIdentityLink {
  static const int maximumEntityIdLength = 200;
  static const int maximumAccountScopeIdLength = 128;

  final PersistedIdentityLink identity;
  final String accountScopeId;
  final EventIdentityRole role;

  EventParticipantIdentityLink({
    required this.identity,
    required String accountScopeId,
    this.role = EventIdentityRole.participant,
  }) : accountScopeId = accountScopeId.trim() {
    if (!EntityIdentity.isValid(identity.entityId) ||
        identity.entityId.length > maximumEntityIdLength ||
        this.accountScopeId.isEmpty ||
        this.accountScopeId.length > maximumAccountScopeIdLength ||
        identity.entityType != EntityType.person) {
      throw const EntityDomainException('invalid_event_participant_identity');
    }
  }

  Map<String, Object?> toJson() => {
        'entityId': identity.entityId,
        'entityType': identity.entityType.name,
        'schemaVersion': identity.schemaVersion,
        'role': role.name,
        'accountScopeId': accountScopeId,
      };

  static EventParticipantIdentityLink? tryFromJson(Object? value) {
    if (value == null || value is! Map) return null;
    if (value.keys.any((key) => key is! String)) return null;
    final map = Map<String, Object?>.from(value);
    if (map.keys.toSet().difference(const {
      'entityId',
      'entityType',
      'schemaVersion',
      'role',
      'accountScopeId',
    }).isNotEmpty) {
      return null;
    }
    final entityId = map['entityId'];
    final schemaVersion = map['schemaVersion'];
    final accountScopeId = map['accountScopeId'];
    if (entityId is! String ||
        !EntityIdentity.isValid(entityId) ||
        entityId.length > maximumEntityIdLength ||
        accountScopeId is! String ||
        accountScopeId.trim().isEmpty ||
        accountScopeId.trim().length > maximumAccountScopeIdLength ||
        map['entityType'] != EntityType.person.name ||
        map['role'] != EventIdentityRole.participant.name ||
        schemaVersion is! int ||
        schemaVersion != PersistedIdentityLink.currentSchemaVersion) {
      return null;
    }
    return EventParticipantIdentityLink(
      identity: PersistedIdentityLink(
        entityId: entityId,
        entityType: EntityType.person,
        schemaVersion: schemaVersion,
      ),
      accountScopeId: accountScopeId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventParticipantIdentityLink &&
          other.identity == identity &&
          other.accountScopeId == accountScopeId &&
          other.role == role;

  @override
  int get hashCode => Object.hash(identity, accountScopeId, role);

  @override
  String toString() => 'EventParticipantIdentityLink(role: ${role.name})';
}
