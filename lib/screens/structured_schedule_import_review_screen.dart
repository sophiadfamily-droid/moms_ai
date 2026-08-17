import 'package:flutter/material.dart';

import '../models/structured_schedule_import.dart';
import '../services/structured_schedule_import_review_service.dart';
import '../theme/app_theme.dart';

final class StructuredScheduleSubjectChoice {
  const StructuredScheduleSubjectChoice({
    required this.entityId,
    required this.label,
  });

  final String entityId;
  final String label;
}

final class StructuredScheduleImportReviewScreen extends StatefulWidget {
  const StructuredScheduleImportReviewScreen({
    super.key,
    required this.initialReview,
    required this.subjects,
    required this.onValidated,
    this.reviewService = const StructuredScheduleImportReviewService(),
  });

  final StructuredScheduleImportReview initialReview;
  final List<StructuredScheduleSubjectChoice> subjects;
  final Future<void> Function(List<StructuredScheduleProposal> proposals)
      onValidated;
  final StructuredScheduleImportReviewService reviewService;

  @override
  State<StructuredScheduleImportReviewScreen> createState() =>
      _StructuredScheduleImportReviewScreenState();
}

final class _StructuredScheduleImportReviewScreenState
    extends State<StructuredScheduleImportReviewScreen> {
  late StructuredScheduleImportReview _review;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _review = widget.initialReview;
  }

  @override
  Widget build(BuildContext context) {
    final keptCount = _review.proposals.where((item) => item.isKept).length;
    final clearPendingCount = _review.proposals
        .where(
          (item) =>
              item.state == StructuredScheduleProposalState.pendingReview &&
              item.isComplete,
        )
        .length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                children: [
                  _summaryCard(),
                  if (clearPendingCount > 0) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('schedule-import-accept-clear'),
                      onPressed: () => setState(() {
                        _review = widget.reviewService.acceptAllClear(_review);
                        _error = null;
                      }),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.roseGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      icon: const Icon(Icons.done_all),
                      label: Text(
                        clearPendingCount == 1
                            ? 'Valider l’information sûre'
                            : 'Valider les informations sûres',
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Informations trouvées',
                    style: TextStyle(
                      color: AppTheme.brown,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final proposal in _review.proposals) ...[
                    _proposalCard(proposal),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      key: const ValueKey('schedule-import-error'),
                      style: const TextStyle(
                        color: Color(0xFF9B3A32),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('schedule-import-continue'),
                    onPressed: _review.state ==
                                StructuredScheduleReviewState.readyToApply &&
                            !_submitting
                        ? _submit
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.roseGold,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.taupe.withValues(alpha: 0.18),
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            keptCount == 1
                                ? 'Continuer avec 1 information'
                                : 'Continuer avec $keptCount informations',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 20, 14),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Retour',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vérifier l’import',
                    style: TextStyle(
                      color: AppTheme.brown,
                      fontFamily: AppTheme.displayFontFamily,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Une seule vérification avant d’enregistrer.',
                    style: TextStyle(
                      color: AppTheme.taupe,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _summaryCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFCFA), Color(0xFFF7E7E1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              color: AppTheme.roseGold.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.roseGold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: AppTheme.roseGold,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Document de ${_review.initiatedForSubjectLabel}',
                    style: const TextStyle(
                      color: AppTheme.brown,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_review.proposals.length} information(s) trouvée(s). '
                    'Vérifie seulement les lignes signalées.',
                    style: const TextStyle(
                      color: AppTheme.taupe,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _proposalCard(StructuredScheduleProposal proposal) {
    final rejected = proposal.state == StructuredScheduleProposalState.rejected;
    final verified = proposal.isKept;
    return AnimatedOpacity(
      opacity: rejected ? 0.55 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey('schedule-import-proposal-${proposal.proposalId}'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: proposal.uncertainties.isNotEmpty && !rejected
                ? const Color(0xFFF0B08C)
                : Colors.white,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.roseGold.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _targetIcon(proposal.target),
                    color: AppTheme.roseGold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proposal.title,
                        style: const TextStyle(
                          color: AppTheme.brown,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${proposal.subjectLabel ?? 'Personne à vérifier'} · '
                        '${_targetLabel(proposal.target)}',
                        style: const TextStyle(
                          color: AppTheme.taupe,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (verified)
                  const Icon(Icons.verified, color: Color(0xFF4D8C72))
                else if (rejected)
                  const Icon(Icons.remove_circle_outline)
                else
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFC86F4B),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _scheduleLabel(proposal),
              style: const TextStyle(
                color: AppTheme.brown,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (proposal.place != null) ...[
              const SizedBox(height: 6),
              Text(
                proposal.place!,
                style: const TextStyle(color: AppTheme.taupe),
              ),
            ],
            if (!rejected) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: ValueKey(
                        'schedule-import-edit-${proposal.proposalId}',
                      ),
                      onPressed: () => _editProposal(proposal),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(verified ? 'Modifier' : 'Vérifier'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    key: ValueKey(
                      'schedule-import-reject-${proposal.proposalId}',
                    ),
                    tooltip: 'Ne pas enregistrer cette ligne',
                    onPressed: () => setState(() {
                      _review = widget.reviewService.rejectProposal(
                        _review,
                        proposal.proposalId,
                      );
                      _error = null;
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editProposal(StructuredScheduleProposal proposal) async {
    final title = TextEditingController(text: proposal.title);
    final date = TextEditingController(
      text: proposal.dateIso == null ? '' : _dateForDisplay(proposal.dateIso),
    );
    final start = TextEditingController(text: proposal.startTime ?? '');
    final end = TextEditingController(text: proposal.endTime ?? '');
    final place = TextEditingController(text: proposal.place ?? '');
    var target = proposal.target;
    var temporalKind = proposal.temporalKind;
    var selectedSubjectId =
        proposal.subjectEntityId ?? _review.initiatedForSubjectEntityId;
    var weekdays = proposal.weekdays.toSet();
    String? sheetError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final subjects = _subjectChoices(selectedSubjectId, proposal);
          final availableTargets =
              temporalKind == StructuredScheduleTemporalKind.recurringWeekly
                  ? StructuredScheduleTarget.values
                      .where((item) => item != StructuredScheduleTarget.event)
                      .toList()
                  : StructuredScheduleTarget.values;
          if (!availableTargets.contains(target)) {
            target = StructuredScheduleTarget.activitySchedule;
          }
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.90,
              ),
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(32),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.taupe.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Vérifier cette information',
                      style: TextStyle(
                        color: AppTheme.brown,
                        fontFamily: AppTheme.displayFontFamily,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey('schedule-import-title'),
                      controller: title,
                      decoration: _inputDecoration('Nom'),
                    ),
                    const SizedBox(height: 14),
                    if (temporalKind == StructuredScheduleTemporalKind.dated)
                      TextField(
                        key: const ValueKey('schedule-import-date'),
                        controller: date,
                        decoration: _inputDecoration(
                          'Date',
                          hint: 'JJ/MM/AAAA',
                        ),
                      )
                    else ...[
                      const Text(
                        'Jours',
                        style: TextStyle(
                          color: AppTheme.brown,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (var day = DateTime.monday;
                              day <= DateTime.sunday;
                              day++)
                            FilterChip(
                              label: Text(_weekdayShort(day)),
                              selected: weekdays.contains(day),
                              onSelected: (selected) => setSheetState(() {
                                if (selected) {
                                  weekdays.add(day);
                                } else {
                                  weekdays.remove(day);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('schedule-import-start-time'),
                            controller: start,
                            decoration: _inputDecoration(
                              'Début',
                              hint: '09:00',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('schedule-import-end-time'),
                            controller: end,
                            decoration: _inputDecoration(
                              'Fin',
                              hint: '10:00',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('schedule-import-place'),
                      controller: place,
                      decoration: _inputDecoration('Lieu', hint: 'Si indiqué'),
                    ),
                    const SizedBox(height: 8),
                    Theme(
                      data: Theme.of(sheetContext).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        key: const ValueKey('schedule-import-more-options'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: const Text(
                          'Personne et type de planning',
                          style: TextStyle(
                            color: AppTheme.brown,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text('Modifier seulement si besoin'),
                        children: [
                          DropdownButtonFormField<String>(
                            key: const ValueKey('schedule-import-subject'),
                            initialValue: subjects.any(
                              (item) => item.entityId == selectedSubjectId,
                            )
                                ? selectedSubjectId
                                : subjects.first.entityId,
                            decoration: _inputDecoration('Personne concernée'),
                            items: subjects
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.entityId,
                                    child: Text(item.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setSheetState(
                              () => selectedSubjectId =
                                  value ?? selectedSubjectId,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<StructuredScheduleTarget>(
                            key: const ValueKey('schedule-import-target'),
                            initialValue: target,
                            decoration: _inputDecoration('Où l’enregistrer'),
                            items: availableTargets
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(_targetLabel(item)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setSheetState(
                              () => target = value ?? target,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<StructuredScheduleTemporalKind>(
                            segments: const [
                              ButtonSegment(
                                value: StructuredScheduleTemporalKind.dated,
                                label: Text('Une date'),
                              ),
                              ButtonSegment(
                                value: StructuredScheduleTemporalKind
                                    .recurringWeekly,
                                label: Text('Chaque semaine'),
                              ),
                            ],
                            selected: {temporalKind},
                            onSelectionChanged: (values) => setSheetState(() {
                              temporalKind = values.single;
                              if (temporalKind ==
                                      StructuredScheduleTemporalKind
                                          .recurringWeekly &&
                                  target == StructuredScheduleTarget.event) {
                                target =
                                    StructuredScheduleTarget.activitySchedule;
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                    if (sheetError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        sheetError!,
                        key: const ValueKey('schedule-import-sheet-error'),
                        style: const TextStyle(
                          color: Color(0xFF9B3A32),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('schedule-import-save-correction'),
                        onPressed: () {
                          try {
                            final subject = subjects.firstWhere(
                              (item) => item.entityId == selectedSubjectId,
                            );
                            final corrected = StructuredScheduleProposal(
                              schemaVersion: proposal.schemaVersion,
                              proposalId: proposal.proposalId,
                              target: target,
                              temporalKind: temporalKind,
                              title: title.text.trim(),
                              subjectEntityId: subject.entityId,
                              subjectLabel: subject.label,
                              dateIso: temporalKind ==
                                      StructuredScheduleTemporalKind.dated
                                  ? _dateToIso(date.text)
                                  : null,
                              weekdays: temporalKind ==
                                      StructuredScheduleTemporalKind
                                          .recurringWeekly
                                  ? weekdays.toList()
                                  : const [],
                              startTime: start.text.trim(),
                              endTime: end.text.trim(),
                              place: place.text.trim().isEmpty
                                  ? null
                                  : place.text.trim(),
                              confidence: StructuredScheduleConfidence.high,
                              uncertainties: const [],
                            );
                            setState(() {
                              _review = widget.reviewService.correctProposal(
                                _review,
                                corrected,
                              );
                              _error = null;
                            });
                            Navigator.pop(sheetContext);
                          } on StructuredScheduleImportException {
                            setSheetState(() {
                              sheetError =
                                  'Vérifie la personne, le jour et les horaires.';
                            });
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.roseGold,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Enregistrer la correction'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<StructuredScheduleSubjectChoice> _subjectChoices(
    String selectedSubjectId,
    StructuredScheduleProposal proposal,
  ) {
    final values = <StructuredScheduleSubjectChoice>[...widget.subjects];
    if (!values.any((item) => item.entityId == selectedSubjectId)) {
      values.add(
        StructuredScheduleSubjectChoice(
          entityId: selectedSubjectId,
          label: proposal.subjectLabel ?? _review.initiatedForSubjectLabel,
        ),
      );
    }
    if (values.isEmpty) {
      values.add(
        StructuredScheduleSubjectChoice(
          entityId: _review.initiatedForSubjectEntityId,
          label: _review.initiatedForSubjectLabel,
        ),
      );
    }
    return values;
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final proposals = widget.reviewService.validatedProposals(_review);
      await widget.onValidated(proposals);
      if (!mounted) return;
      Navigator.pop(context, proposals);
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Je n’ai pas pu préparer ces informations. Tu peux réessayer.';
      });
    }
  }
}

InputDecoration _inputDecoration(String label, {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    );

String _targetLabel(StructuredScheduleTarget target) => switch (target) {
      StructuredScheduleTarget.event => 'Agenda',
      StructuredScheduleTarget.workSchedule => 'Planning de travail',
      StructuredScheduleTarget.schoolSchedule => 'École ou crèche',
      StructuredScheduleTarget.activitySchedule => 'Activités',
      StructuredScheduleTarget.otherSchedule => 'Autre planning',
    };

IconData _targetIcon(StructuredScheduleTarget target) => switch (target) {
      StructuredScheduleTarget.event => Icons.event_outlined,
      StructuredScheduleTarget.workSchedule => Icons.work_outline,
      StructuredScheduleTarget.schoolSchedule => Icons.school_outlined,
      StructuredScheduleTarget.activitySchedule =>
        Icons.self_improvement_outlined,
      StructuredScheduleTarget.otherSchedule => Icons.calendar_view_week,
    };

String _scheduleLabel(StructuredScheduleProposal proposal) {
  final period = '${proposal.startTime ?? 'heure à vérifier'} – '
      '${proposal.endTime ?? 'heure à vérifier'}'
      '${proposal.spansMidnight ? ' (le lendemain)' : ''}';
  if (proposal.temporalKind == StructuredScheduleTemporalKind.dated) {
    return '${_dateForDisplay(proposal.dateIso)} · $period';
  }
  final days = proposal.weekdays.isEmpty
      ? 'jours à vérifier'
      : proposal.weekdays.map(_weekdayLong).join(', ');
  return '$days · $period';
}

String _dateForDisplay(String? isoDate) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate ?? '');
  if (match == null) return 'date à vérifier';
  return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
}

String _dateToIso(String value) {
  final trimmed = value.trim();
  final french = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(trimmed);
  if (french != null) {
    return '${french.group(3)}-${french.group(2)}-${french.group(1)}';
  }
  return trimmed;
}

String _weekdayShort(int day) => switch (day) {
      DateTime.monday => 'Lun',
      DateTime.tuesday => 'Mar',
      DateTime.wednesday => 'Mer',
      DateTime.thursday => 'Jeu',
      DateTime.friday => 'Ven',
      DateTime.saturday => 'Sam',
      DateTime.sunday => 'Dim',
      _ => '?',
    };

String _weekdayLong(int day) => switch (day) {
      DateTime.monday => 'lundi',
      DateTime.tuesday => 'mardi',
      DateTime.wednesday => 'mercredi',
      DateTime.thursday => 'jeudi',
      DateTime.friday => 'vendredi',
      DateTime.saturday => 'samedi',
      DateTime.sunday => 'dimanche',
      _ => 'jour inconnu',
    };
