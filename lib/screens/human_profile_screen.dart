import 'package:flutter/material.dart';

import '../models/human/human_model.dart';
import '../models/human/human_model_persistence.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/human/human_model_edit_service.dart';

class HumanProfileScreen extends StatefulWidget {
  const HumanProfileScreen({
    super.key,
    required this.legacyProfile,
    this.editService,
    this.accountScopeId,
    this.onLegacyProfileUpdated,
  });

  final UserProfile legacyProfile;
  final HumanModelEditService? editService;
  final String? accountScopeId;
  final ValueChanged<UserProfile>? onLegacyProfileUpdated;

  @override
  State<HumanProfileScreen> createState() => _HumanProfileScreenState();
}

class _HumanProfileScreenState extends State<HumanProfileScreen> {
  HumanModelEditService? _editService;
  HumanModelLocalState? _state;
  bool _loading = true;
  bool _saving = false;
  String? _message;

  String? get _scope => widget.accountScopeId ?? AuthService.currentUserId;
  HumanModel? get _model => _state?.model;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scope = _scope;
    if (scope == null || scope.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Ta session doit être rétablie avant de continuer.';
        });
      }
      return;
    }
    final service =
        widget.editService ?? await HumanModelEditService.createProduction();
    HumanModelLocalState? state;
    try {
      state = await service.load(scope);
    } on Object {
      if (mounted) {
        setState(() {
          _editService = service;
          _loading = false;
          _message = 'Zélia n’a pas pu charger ces informations.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _editService = service;
      _state = state;
      _loading = false;
      _message = state == null
          ? 'Ton profil humain n’est pas encore disponible.'
          : null;
    });
  }

  Future<bool> _commit(HumanModel Function(HumanModel) transform) async {
    final scope = _scope;
    final service = _editService;
    if (scope == null || service == null || _saving) return false;
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await service.commit(
      accountScopeId: scope,
      transform: transform,
    );
    final state = result.state ?? await service.load(scope);
    if (!mounted) return false;
    setState(() {
      _state = state;
      _saving = false;
      _message = _messageFor(result.status);
    });
    if (result.status == HumanModelEditStatus.success && state != null) {
      final persisted = await service.persistLegacyProjection(
        model: state.model,
        legacy: widget.legacyProfile,
      );
      widget.onLegacyProfileUpdated?.call(persisted);
    }
    return result.status == HumanModelEditStatus.success ||
        result.status == HumanModelEditStatus.pendingSync;
  }

  String _messageFor(HumanModelEditStatus status) => switch (status) {
        HumanModelEditStatus.success => 'Modification enregistrée.',
        HumanModelEditStatus.pendingSync =>
          'Modification conservée. Elle sera synchronisée dès que possible.',
        HumanModelEditStatus.revisionConflict =>
          'Ces informations ont été modifiées sur un autre appareil. Vérifie la version actuelle avant d’enregistrer à nouveau.',
        HumanModelEditStatus.validationFailure =>
          'Certaines informations sont incohérentes. Vérifie le formulaire.',
        HumanModelEditStatus.networkUnavailable =>
          'La connexion semble indisponible. Réessaie dans un instant.',
        HumanModelEditStatus.notFound =>
          'Ton profil humain n’est pas encore disponible.',
        HumanModelEditStatus.needsConfirmation =>
          'Une modification attend déjà une vérification. Termine-la avant d’en ajouter une autre.',
        HumanModelEditStatus.storageFailure =>
          'Zélia n’a pas pu conserver cette modification.',
        _ =>
          'Zélia rencontre un problème temporaire. Tes données ne sont pas perdues.',
      };

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon organisation')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : model == null
                ? _emptyState()
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Les personnes et lieux qui comptent pour toi',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ajoute seulement ce qui t’est utile. Tu pourras toujours compléter plus tard.',
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        _statusBanner(_message!),
                      ],
                      if (_saving) const LinearProgressIndicator(),
                      const SizedBox(height: 18),
                      _section(
                        icon: Icons.person_outline,
                        title: 'Moi',
                        subtitle: _personName(
                          model.personById(model.primaryPersonId),
                        ),
                        onTap: () => _editPerson(
                          model.personById(model.primaryPersonId)!,
                          primary: true,
                        ),
                      ),
                      _section(
                        icon: Icons.people_outline,
                        title: 'Personnes',
                        subtitle: model.persons.length <= 1
                            ? 'Aucune autre personne ajoutée'
                            : '${model.persons.length - 1} autre(s) personne(s)',
                        onTap: _showPeople,
                      ),
                      _section(
                        icon: Icons.link_outlined,
                        title: 'Relations',
                        subtitle: model.relationships.isEmpty
                            ? 'Aucune relation renseignée'
                            : '${model.relationships.length} relation(s)',
                        onTap: _showRelationships,
                      ),
                      _section(
                        icon: Icons.groups_outlined,
                        title: 'Foyers',
                        subtitle: model.households.isEmpty
                            ? 'Aucun foyer renseigné'
                            : '${model.households.length} foyer(s)',
                        onTap: _showHouseholds,
                      ),
                      _section(
                        icon: Icons.home_outlined,
                        title: 'Domiciles',
                        subtitle: model.residences.isEmpty
                            ? 'Aucun domicile renseigné'
                            : '${model.residences.length} domicile(s)',
                        onTap: _showResidences,
                      ),
                      _section(
                        icon: Icons.volunteer_activism_outlined,
                        title: 'Responsabilités',
                        subtitle: model.responsibilities.isEmpty
                            ? 'Aucune responsabilité renseignée'
                            : '${model.responsibilities.length} responsabilité(s)',
                        onTap: _showResponsibilities,
                      ),
                      _section(
                        icon: Icons.help_outline,
                        title: 'Informations à confirmer',
                        subtitle: _state?.pendingMutation == null
                            ? 'Aucune information en attente'
                            : '1 information à confirmer',
                        onTap: _showPendingProposal,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _message ?? 'Tu pourras compléter cette section plus tard.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );

  Widget _statusBanner(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4E8F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      );

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          button: true,
          label: '$title, $subtitle',
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );

  Future<void> _showPeople() => _showListSheet(
        title: 'Personnes',
        empty: 'Aucune autre personne ajoutée',
        addLabel: 'Ajouter une personne',
        items: [
          for (final person in _model!.persons
              .where((item) => item.id != _model!.primaryPersonId))
            ListTile(
              title: Text(_personName(person)),
              subtitle: Text(_personStatusLabel(person.status)),
              onTap: () => _editPerson(person),
            ),
        ],
        onAdd: () => _editPerson(null),
      );

  Future<void> _editPerson(HumanPerson? person, {bool primary = false}) async {
    final name = TextEditingController(text: person?.displayName ?? '');
    final birth = TextEditingController(
      text:
          person?.customFields['birthDate']?.toString().split('T').first ?? '',
    );
    var status = person?.status ?? HumanPersonStatus.active;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(person == null ? 'Ajouter une personne' : 'Personne'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nom d’affichage (facultatif)',
                  ),
                ),
                TextField(
                  controller: birth,
                  decoration: const InputDecoration(
                    labelText: 'Date de naissance (facultative)',
                    hintText: 'AAAA-MM-JJ',
                  ),
                ),
                DropdownButtonFormField<HumanPersonStatus>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Situation'),
                  items: HumanPersonStatus.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_personStatusLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => status = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final parsedBirth = DateTime.tryParse(birth.text.trim());
    await _commit((model) {
      final updated = person == null
          ? _editService!.newPerson(
              model.accountScopeId,
              displayName: name.text,
              birthDate: parsedBirth,
            )
          : person.copyWith(
              displayName: name.text.trim(),
              clearDisplayName: name.text.trim().isEmpty,
              status: primary && status != HumanPersonStatus.active
                  ? HumanPersonStatus.active
                  : status,
              evidence: _confirmed,
              customFields: {
                ...person.customFields,
                if (parsedBirth != null)
                  'birthDate': parsedBirth.toUtc().toIso8601String(),
              }..removeWhere(
                  (key, _) => key == 'birthDate' && parsedBirth == null,
                ),
            );
      return model.copyWith(
        persons: person == null
            ? [...model.persons, updated]
            : model.persons
                .map((item) => item.id == person.id ? updated : item)
                .toList(),
      );
    });
  }

  Future<void> _showRelationships() => _showListSheet(
        title: 'Relations',
        empty: 'Aucune relation renseignée',
        addLabel: 'Ajouter une relation',
        items: [
          for (final relation in _model!.relationships)
            ListTile(
              title: Text(
                '${_personName(_model!.personById(relation.sourcePersonId))} · ${_relationshipLabel(relation)} · ${_personName(_model!.personById(relation.targetPersonId))}',
              ),
              subtitle: Text(_recordStatusLabel(relation.status)),
              onTap: () => _editRelationship(relation),
            ),
        ],
        onAdd: () => _editRelationship(null),
      );

  Future<void> _editRelationship(HumanRelationship? relation) async {
    if (_model!.persons.length < 2) {
      _setMessage('Ajoute d’abord une autre personne.');
      return;
    }
    var source = relation?.sourcePersonId ?? _model!.primaryPersonId;
    var target = relation?.targetPersonId ??
        _model!.persons.firstWhere((person) => person.id != source).id;
    var type = relation?.type ?? HumanRelationshipTypes.closePerson;
    var status = relation?.status ?? HumanRecordStatus.active;
    final custom = TextEditingController(text: relation?.customType ?? '');
    final period = await _periodAndFieldsDialog(
      title: relation == null ? 'Ajouter une relation' : 'Modifier la relation',
      initialPeriod: relation?.validity,
      fields: (setDialogState) => [
        _personDropdown('Personne source', source, (value) {
          setDialogState(() => source = value);
        }),
        _personDropdown('Personne concernée', target, (value) {
          setDialogState(() => target = value);
        }),
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type de relation'),
          items: HumanRelationshipTypes.known
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_relationshipTypeLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => type = value);
          },
        ),
        if (type == HumanRelationshipTypes.custom)
          TextField(
            controller: custom,
            decoration: const InputDecoration(labelText: 'Relation'),
          ),
        DropdownButtonFormField<HumanRecordStatus>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'État'),
          items: HumanRecordStatus.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_recordStatusLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => status = value);
          },
        ),
      ],
    );
    if (period == null) return;
    await _commit((model) {
      final updated = relation == null
          ? _editService!.newRelationship(
              accountScopeId: model.accountScopeId,
              sourcePersonId: source,
              targetPersonId: target,
              type: type,
              customType: custom.text,
              status: status,
              validity: period,
            )
          : HumanRelationship(
              id: relation.id,
              accountScopeId: relation.accountScopeId,
              sourcePersonId: source,
              targetPersonId: target,
              type: type,
              customType: type == HumanRelationshipTypes.custom
                  ? custom.text.trim()
                  : null,
              status: status,
              validity: period,
              reciprocal: relation.reciprocal,
              evidence: _confirmed,
              structuredNotes: relation.structuredNotes,
            );
      return model.copyWith(
        relationships: relation == null
            ? [...model.relationships, updated]
            : model.relationships
                .map((item) => item.id == relation.id ? updated : item)
                .toList(),
      );
    });
  }

  Future<void> _showHouseholds() => _showListSheet(
        title: 'Foyers',
        empty: 'Aucun foyer renseigné',
        addLabel: 'Ajouter un foyer',
        items: [
          for (final household in _model!.households)
            ListTile(
              title: Text(household.displayName ?? 'Foyer sans libellé'),
              subtitle: Text(
                '${_householdStatusLabel(household.status)} · ${_model!.memberships.where((item) => item.householdId == household.id).length} membre(s)',
              ),
              onTap: () => _editHousehold(household),
              trailing: IconButton(
                tooltip: 'Gérer les membres',
                icon: const Icon(Icons.group_add_outlined),
                onPressed: () => _showMemberships(household),
              ),
            ),
        ],
        onAdd: () => _editHousehold(null),
      );

  Future<void> _showMemberships(HumanHousehold household) {
    final memberships = _model!.memberships
        .where((item) => item.householdId == household.id)
        .toList();
    return _showListSheet(
      title: 'Membres du foyer',
      empty: 'Aucun membre ajouté',
      addLabel: 'Ajouter un membre',
      items: [
        for (final membership in memberships)
          ListTile(
            title: Text(
              _personName(_model!.personById(membership.personId)),
            ),
            subtitle: Text(_membershipRoleLabel(membership.role)),
            trailing: IconButton(
              tooltip: 'Retirer du foyer',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: () async {
                Navigator.pop(context);
                final confirmed = await _confirm(
                  'Retirer cette appartenance ?',
                  'La personne et son historique seront conservés.',
                );
                if (!confirmed) return;
                await _commit(
                  (model) => model.copyWith(
                    memberships: model.memberships
                        .map(
                          (item) => item.id == membership.id
                              ? item.copyWith(
                                  validity: HumanValidityPeriod(
                                    validFrom: item.validity.validFrom,
                                    validUntil:
                                        item.validity.validFrom?.isAfter(
                                                  DateTime.now().toUtc(),
                                                ) ==
                                                true
                                            ? item.validity.validFrom
                                            : DateTime.now().toUtc(),
                                  ),
                                  evidence: _confirmed,
                                )
                              : item,
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
      ],
      onAdd: () => _editMembership(household),
    );
  }

  Future<void> _editHousehold(HumanHousehold? household) async {
    final name = TextEditingController(text: household?.displayName ?? '');
    var status = household?.status ?? HouseholdStatus.primary;
    final period = await _periodAndFieldsDialog(
      title: household == null ? 'Ajouter un foyer' : 'Modifier le foyer',
      initialPeriod: household?.validity,
      fields: (setDialogState) => [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Nom du foyer (facultatif)',
          ),
        ),
        DropdownButtonFormField<HouseholdStatus>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Situation'),
          items: HouseholdStatus.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_householdStatusLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => status = value);
          },
        ),
      ],
    );
    if (period == null) return;
    await _commit((model) {
      final updated = household == null
          ? _editService!.newHousehold(
              model.accountScopeId,
              displayName: name.text,
              status: status,
              validity: period,
            )
          : household.copyWith(
              displayName: name.text.trim(),
              clearDisplayName: name.text.trim().isEmpty,
              status: status,
              validity: period,
              evidence: _confirmed,
            );
      return model.copyWith(
        households: household == null
            ? [...model.households, updated]
            : model.households
                .map((item) => item.id == household.id ? updated : item)
                .toList(),
      );
    });
  }

  Future<void> _editMembership(HumanHousehold household) async {
    if (_model!.persons.isEmpty) return;
    var personId = _model!.primaryPersonId;
    var role = HouseholdMembershipRoles.permanentMember;
    final custom = TextEditingController();
    final period = await _periodAndFieldsDialog(
      title: 'Ajouter une appartenance',
      fields: (setDialogState) => [
        _personDropdown('Personne', personId, (value) {
          setDialogState(() => personId = value);
        }),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(labelText: 'Type d’appartenance'),
          items: _membershipRoles
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_membershipRoleLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => role = value);
          },
        ),
        if (role == HouseholdMembershipRoles.custom)
          TextField(
            controller: custom,
            decoration: const InputDecoration(labelText: 'Rôle'),
          ),
      ],
    );
    if (period == null) return;
    await _commit(
      (model) => model.copyWith(
        memberships: [
          ...model.memberships,
          _editService!.newMembership(
            accountScopeId: model.accountScopeId,
            householdId: household.id,
            personId: personId,
            role: role,
            customRole: custom.text,
            validity: period,
          ),
        ],
      ),
    );
  }

  Future<void> _showResidences() => _showListSheet(
        title: 'Domiciles',
        empty: 'Aucun domicile renseigné',
        addLabel: 'Ajouter un domicile',
        items: [
          for (final residence in _model!.residences)
            ListTile(
              title: Text(residence.label),
              subtitle: Text(_residenceStatusLabel(residence.status)),
              onTap: () => _editResidence(residence),
            ),
        ],
        onAdd: () => _editResidence(null),
      );

  Future<void> _editResidence(HumanResidence? residence) async {
    final label = TextEditingController(text: residence?.label ?? '');
    var status = residence?.status ?? ResidenceStatus.primary;
    final selectedPeople = <String>{...?residence?.personIds};
    final selectedHouseholds = <String>{...?residence?.householdIds};
    final period = await _periodAndFieldsDialog(
      title: residence == null ? 'Ajouter un domicile' : 'Modifier le domicile',
      initialPeriod: residence?.validity,
      fields: (setDialogState) => [
        TextField(
          controller: label,
          decoration: const InputDecoration(labelText: 'Libellé'),
        ),
        DropdownButtonFormField<ResidenceStatus>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Situation'),
          items: ResidenceStatus.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_residenceStatusLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => status = value);
          },
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Personnes associées'),
        ),
        for (final person in _model!.persons)
          CheckboxListTile(
            value: selectedPeople.contains(person.id),
            title: Text(_personName(person)),
            onChanged: (selected) => setDialogState(() {
              selected == true
                  ? selectedPeople.add(person.id)
                  : selectedPeople.remove(person.id);
            }),
          ),
        if (_model!.households.isNotEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Foyers associés'),
          ),
        for (final household in _model!.households)
          CheckboxListTile(
            value: selectedHouseholds.contains(household.id),
            title: Text(household.displayName ?? 'Foyer sans libellé'),
            onChanged: (selected) => setDialogState(() {
              selected == true
                  ? selectedHouseholds.add(household.id)
                  : selectedHouseholds.remove(household.id);
            }),
          ),
      ],
    );
    if (period == null || label.text.trim().isEmpty) return;
    await _commit((model) {
      final updated = residence == null
          ? _editService!.newResidence(
              accountScopeId: model.accountScopeId,
              label: label.text,
              personIds: selectedPeople.toList(),
              householdIds: selectedHouseholds.toList(),
              status: status,
              validity: period,
            )
          : residence.copyWith(
              label: label.text.trim(),
              personIds: selectedPeople.toList(),
              householdIds: selectedHouseholds.toList(),
              status: status,
              validity: period,
              evidence: _confirmed,
            );
      return model.copyWith(
        residences: residence == null
            ? [...model.residences, updated]
            : model.residences
                .map((item) => item.id == residence.id ? updated : item)
                .toList(),
      );
    });
  }

  Future<void> _showResponsibilities() => _showListSheet(
        title: 'Responsabilités',
        empty: 'Aucune responsabilité renseignée',
        addLabel: 'Ajouter une responsabilité',
        items: [
          for (final responsibility in _model!.responsibilities)
            ListTile(
              title: Text(_responsibilityLabel(responsibility)),
              subtitle: Text(
                '${_personName(_model!.personById(responsibility.responsiblePersonId))} → ${_personName(_model!.personById(responsibility.subjectPersonId))}',
              ),
              onTap: () => _editResponsibility(responsibility),
            ),
        ],
        onAdd: () => _editResponsibility(null),
        footer:
            'Ces informations décrivent une organisation déclarée. Elles ne constituent pas une décision juridique.',
      );

  Future<void> _editResponsibility(
    HumanResponsibility? responsibility,
  ) async {
    if (_model!.persons.length < 2) {
      _setMessage('Ajoute d’abord une autre personne.');
      return;
    }
    var responsible =
        responsibility?.responsiblePersonId ?? _model!.primaryPersonId;
    var subject = responsibility?.subjectPersonId ??
        _model!.persons.firstWhere((person) => person.id != responsible).id;
    var type = responsibility?.type ?? HumanResponsibilityTypes.care;
    var status = responsibility?.status ?? HumanRecordStatus.active;
    final custom =
        TextEditingController(text: responsibility?.customType ?? '');
    final scope = TextEditingController(text: responsibility?.scope ?? '');
    final period = await _periodAndFieldsDialog(
      title: responsibility == null
          ? 'Ajouter une responsabilité'
          : 'Modifier la responsabilité',
      initialPeriod: responsibility?.validity,
      fields: (setDialogState) => [
        _personDropdown('Personne responsable', responsible, (value) {
          setDialogState(() => responsible = value);
        }),
        _personDropdown('Personne concernée', subject, (value) {
          setDialogState(() => subject = value);
        }),
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: _responsibilityTypes
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_responsibilityTypeLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => type = value);
          },
        ),
        if (type == HumanResponsibilityTypes.custom)
          TextField(
            controller: custom,
            decoration: const InputDecoration(labelText: 'Type personnalisé'),
          ),
        TextField(
          controller: scope,
          decoration: const InputDecoration(
            labelText: 'Précision (facultative)',
          ),
        ),
        DropdownButtonFormField<HumanRecordStatus>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'État'),
          items: HumanRecordStatus.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_recordStatusLabel(value)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setDialogState(() => status = value);
          },
        ),
      ],
    );
    if (period == null) return;
    await _commit((model) {
      final updated = responsibility == null
          ? _editService!.newResponsibility(
              accountScopeId: model.accountScopeId,
              responsiblePersonId: responsible,
              subjectPersonId: subject,
              type: type,
              customType: custom.text,
              scope: scope.text,
              status: status,
              validity: period,
            )
          : HumanResponsibility(
              id: responsibility.id,
              accountScopeId: responsibility.accountScopeId,
              responsiblePersonId: responsible,
              subjectPersonId: subject,
              type: type,
              customType: type == HumanResponsibilityTypes.custom
                  ? custom.text.trim()
                  : null,
              scope: scope.text.trim().isEmpty ? null : scope.text.trim(),
              status: status,
              validity: period,
              evidence: _confirmed,
            );
      return model.copyWith(
        responsibilities: responsibility == null
            ? [...model.responsibilities, updated]
            : model.responsibilities
                .map((item) => item.id == responsibility.id ? updated : item)
                .toList(),
      );
    });
  }

  Future<void> _showPendingProposal() async {
    final pending = _state?.pendingMutation;
    if (pending == null) {
      _setMessage('Aucune information n’attend ta confirmation.');
      return;
    }
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Information à confirmer'),
        content: const Text(
          'Une information de ton ancien profil peut compléter ton organisation. Veux-tu la conserver ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Plus tard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'reject'),
            child: const Text('Rejeter'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'accept'),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (decision == null || decision == 'later') return;
    final result = await _editService!.resolveLegacyProposal(
      accountScopeId: _scope!,
      accepted: decision == 'accept',
    );
    if (!mounted) return;
    setState(() {
      _state = result.state;
      _message = _messageFor(result.status);
    });
  }

  Future<void> _showListSheet({
    required String title,
    required String empty,
    required String addLabel,
    required List<Widget> items,
    required VoidCallback onAdd,
    String? footer,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: .86,
          child: Column(
            children: [
              ListTile(
                title: Text(title),
                trailing: IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text(empty))
                    : ListView(children: items),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(footer),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onAdd();
                    },
                    icon: const Icon(Icons.add),
                    label: Text(addLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<HumanValidityPeriod?> _periodAndFieldsDialog({
    required String title,
    HumanValidityPeriod? initialPeriod,
    required List<Widget> Function(StateSetter setDialogState) fields,
  }) async {
    final from = TextEditingController(
      text: initialPeriod?.validFrom?.toIso8601String().split('T').first ?? '',
    );
    final until = TextEditingController(
      text: initialPeriod?.validUntil?.toIso8601String().split('T').first ?? '',
    );
    return showDialog<HumanValidityPeriod>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...fields(setDialogState),
                  ExpansionTile(
                    title: const Text('Période (facultative)'),
                    children: [
                      TextField(
                        controller: from,
                        decoration: const InputDecoration(
                          labelText: 'Début',
                          hintText: 'AAAA-MM-JJ',
                        ),
                      ),
                      TextField(
                        controller: until,
                        decoration: const InputDecoration(
                          labelText: 'Fin',
                          hintText: 'AAAA-MM-JJ',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final start = _optionalDate(from.text);
                final end = _optionalDate(until.text);
                if (start != null && end != null && end.isBefore(start)) {
                  return;
                }
                Navigator.pop(
                  context,
                  HumanValidityPeriod(validFrom: start, validUntil: end),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  DropdownButtonFormField<String> _personDropdown(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: _model!.persons
            .map(
              (person) => DropdownMenuItem(
                value: person.id,
                child: Text(_personName(person)),
              ),
            )
            .toList(),
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      );

  void _setMessage(String message) {
    if (mounted) setState(() => _message = message);
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;

  DateTime? _optionalDate(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : DateTime.tryParse(trimmed)?.toUtc();
  }

  String _personName(HumanPerson? person) =>
      person?.displayName?.trim().isNotEmpty == true
          ? person!.displayName!.trim()
          : 'Personne sans nom';
}

const _confirmed = HumanEvidence(
  source: HumanInformationSource.explicitUserInput,
  confirmation: HumanConfirmationStatus.confirmed,
);

const _membershipRoles = [
  HouseholdMembershipRoles.permanentMember,
  HouseholdMembershipRoles.alternatingMember,
  HouseholdMembershipRoles.temporaryMember,
  HouseholdMembershipRoles.responsiblePerson,
  HouseholdMembershipRoles.dependent,
  HouseholdMembershipRoles.hostedGuest,
  HouseholdMembershipRoles.custom,
];

const _responsibilityTypes = [
  HumanResponsibilityTypes.parental,
  HumanResponsibilityTypes.custody,
  HumanResponsibilityTypes.accompaniment,
  HumanResponsibilityTypes.care,
  HumanResponsibilityTypes.dailyAssistance,
  HumanResponsibilityTypes.transport,
  HumanResponsibilityTypes.emergency,
  HumanResponsibilityTypes.temporary,
  HumanResponsibilityTypes.delegation,
  HumanResponsibilityTypes.custom,
];

String _personStatusLabel(HumanPersonStatus status) => switch (status) {
      HumanPersonStatus.active => 'Active',
      HumanPersonStatus.historical => 'Historique',
      HumanPersonStatus.absent => 'Absente',
      HumanPersonStatus.deceased => 'Décédée',
    };

String _recordStatusLabel(HumanRecordStatus status) => switch (status) {
      HumanRecordStatus.active => 'Actuelle',
      HumanRecordStatus.ended => 'Terminée',
      HumanRecordStatus.historical => 'Historique',
      HumanRecordStatus.uncertain => 'À confirmer',
    };

String _householdStatusLabel(HouseholdStatus status) => switch (status) {
      HouseholdStatus.primary => 'Principal',
      HouseholdStatus.secondary => 'Secondaire',
      HouseholdStatus.temporary => 'Temporaire',
      HouseholdStatus.historical => 'Historique',
    };

String _residenceStatusLabel(ResidenceStatus status) => switch (status) {
      ResidenceStatus.primary => 'Principal',
      ResidenceStatus.secondary => 'Secondaire',
      ResidenceStatus.temporary => 'Temporaire',
      ResidenceStatus.historical => 'Historique',
    };

String _relationshipTypeLabel(String type) => switch (type) {
      HumanRelationshipTypes.partner => 'Partenaire',
      HumanRelationshipTypes.spouse => 'Conjoint·e',
      HumanRelationshipTypes.formerPartner => 'Ex-partenaire',
      HumanRelationshipTypes.parent => 'Parent',
      HumanRelationshipTypes.child => 'Enfant',
      HumanRelationshipTypes.sibling => 'Frère ou sœur',
      HumanRelationshipTypes.halfSibling => 'Demi-frère ou demi-sœur',
      HumanRelationshipTypes.stepParent => 'Beau-parent',
      HumanRelationshipTypes.stepChild => 'Bel-enfant',
      HumanRelationshipTypes.grandParent => 'Grand-parent',
      HumanRelationshipTypes.grandChild => 'Petit-enfant',
      HumanRelationshipTypes.guardian => 'Tuteur',
      HumanRelationshipTypes.responsiblePerson => 'Responsable',
      HumanRelationshipTypes.caregiver => 'Aidant',
      HumanRelationshipTypes.caredForPerson => 'Personne aidée',
      HumanRelationshipTypes.fosterFamily => 'Famille d’accueil',
      HumanRelationshipTypes.fosterChild => 'Enfant accueilli',
      HumanRelationshipTypes.closePerson => 'Proche',
      _ => 'Autre relation',
    };

String _relationshipLabel(HumanRelationship relationship) =>
    relationship.type == HumanRelationshipTypes.custom
        ? (relationship.customType ?? 'Autre relation')
        : _relationshipTypeLabel(relationship.type);

String _membershipRoleLabel(String role) => switch (role) {
      HouseholdMembershipRoles.permanentMember => 'Permanent',
      HouseholdMembershipRoles.alternatingMember => 'Alterné',
      HouseholdMembershipRoles.temporaryMember => 'Temporaire',
      HouseholdMembershipRoles.responsiblePerson => 'Responsable',
      HouseholdMembershipRoles.dependent => 'Dépendant',
      HouseholdMembershipRoles.hostedGuest => 'Invité ou hébergé',
      _ => 'Personnalisé',
    };

String _responsibilityTypeLabel(String type) => switch (type) {
      HumanResponsibilityTypes.parental => 'Parentale',
      HumanResponsibilityTypes.custody => 'Garde déclarative',
      HumanResponsibilityTypes.accompaniment => 'Accompagnement',
      HumanResponsibilityTypes.care => 'Prise en charge',
      HumanResponsibilityTypes.dailyAssistance => 'Aide quotidienne',
      HumanResponsibilityTypes.transport => 'Transport',
      HumanResponsibilityTypes.emergency => 'Urgence',
      HumanResponsibilityTypes.temporary => 'Temporaire',
      HumanResponsibilityTypes.delegation => 'Délégation',
      _ => 'Personnalisée',
    };

String _responsibilityLabel(HumanResponsibility responsibility) =>
    responsibility.type == HumanResponsibilityTypes.custom
        ? (responsibility.customType ?? 'Responsabilité personnalisée')
        : _responsibilityTypeLabel(responsibility.type);
