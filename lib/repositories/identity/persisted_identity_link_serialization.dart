import 'dart:collection';

import '../../core/identity/entity_identity.dart';
import '../../core/identity/entity_types.dart';
import '../../core/identity/persisted_identity_link.dart';

enum PersistedIdentityLinkReadStatus {
  absent,
  valid,
  invalid,
  unsupportedVersion,
}

final class PersistedIdentityLinkReadResult {
  final PersistedIdentityLink? link;
  final PersistedIdentityLinkReadStatus status;
  final List<String> _diagnosticCodes;

  PersistedIdentityLinkReadResult._({
    required this.link,
    required this.status,
    required List<String> diagnosticCodes,
  }) : _diagnosticCodes = List.unmodifiable(diagnosticCodes) {
    if (status == PersistedIdentityLinkReadStatus.valid && link == null) {
      throw const EntityDomainException(
        'valid_persisted_identity_link_read_requires_link',
      );
    }
    if (status != PersistedIdentityLinkReadStatus.valid && link != null) {
      throw const EntityDomainException(
        'invalid_persisted_identity_link_read_contains_link',
      );
    }
  }

  List<String> get diagnosticCodes => UnmodifiableListView(_diagnosticCodes);
}

abstract final class PersistedIdentityLinkSerialization {
  static Map<String, Object?> toMap(PersistedIdentityLink link) => {
        'entityId': link.entityId,
        'entityType': link.entityType.name,
        'schemaVersion': link.schemaVersion,
      };

  static PersistedIdentityLinkReadResult fromMap(Object? value) {
    if (value == null) {
      return _result(PersistedIdentityLinkReadStatus.absent);
    }
    if (value is! Map) {
      return _invalid('persisted_identity_link_invalid');
    }

    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        return _invalid('persisted_identity_link_invalid');
      }
      map[entry.key as String] = entry.value;
    }

    final entityId = map['entityId'];
    if (entityId is! String || !EntityIdentity.isValid(entityId)) {
      return _invalid('persisted_identity_link_invalid_entity_id');
    }

    final entityTypeName = map['entityType'];
    if (entityTypeName is! String) {
      return _invalid('persisted_identity_link_invalid_entity_type');
    }
    final entityType = _entityTypeFromName(entityTypeName);
    if (entityType == null || entityType == EntityType.unknown) {
      return _invalid('persisted_identity_link_invalid_entity_type');
    }

    final diagnostics = <String>[];
    final Object? rawVersion = map.containsKey('schemaVersion')
        ? map['schemaVersion']
        : PersistedIdentityLink.currentSchemaVersion;
    if (!map.containsKey('schemaVersion')) {
      diagnostics.add('persisted_identity_link_version_defaulted');
    }
    if (rawVersion is! int || rawVersion < 1) {
      return _invalid('persisted_identity_link_invalid_schema_version');
    }
    if (rawVersion > PersistedIdentityLink.currentSchemaVersion) {
      return _result(
        PersistedIdentityLinkReadStatus.unsupportedVersion,
        diagnostics: const [
          'persisted_identity_link_unsupported_version',
        ],
      );
    }

    return _result(
      PersistedIdentityLinkReadStatus.valid,
      link: PersistedIdentityLink(
        entityId: entityId,
        entityType: entityType,
        schemaVersion: rawVersion,
      ),
      diagnostics: diagnostics,
    );
  }

  static EntityType? _entityTypeFromName(String name) {
    for (final value in EntityType.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static PersistedIdentityLinkReadResult _invalid(String diagnostic) {
    return _result(
      PersistedIdentityLinkReadStatus.invalid,
      diagnostics: [
        'persisted_identity_link_invalid',
        if (diagnostic != 'persisted_identity_link_invalid') diagnostic,
      ],
    );
  }

  static PersistedIdentityLinkReadResult _result(
    PersistedIdentityLinkReadStatus status, {
    PersistedIdentityLink? link,
    List<String> diagnostics = const [],
  }) {
    return PersistedIdentityLinkReadResult._(
      link: link,
      status: status,
      diagnosticCodes: diagnostics,
    );
  }
}
