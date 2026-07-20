import 'life_context_provenance.dart';

/// Free-form historical profile notes.
///
/// These values are preserved verbatim and are not preferences, constraints,
/// goals, memories, or interpreted facts.
final class NotesContext {
  final LifeContextFact<String>? personalNotes;
  final LifeContextFact<String>? adminNotes;
  final LifeContextFact<String>? budgetNotes;

  const NotesContext({
    this.personalNotes,
    this.adminNotes,
    this.budgetNotes,
  });

  Map<String, dynamic> toJson() => {
        'personalNotes': personalNotes?.toJson(),
        'adminNotes': adminNotes?.toJson(),
        'budgetNotes': budgetNotes?.toJson(),
      };
}
