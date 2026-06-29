import 'planning_proposal_engine.dart';

class PlanningProposalSelectionService {
  static int? extractIndex(
    String text,
    List<PlanningProposalOption> options,
  ) {
    final value = text.trim().toLowerCase();

    if (value == "1") return 0;
    if (value == "2") return 1;
    if (value == "3") return 2;

    if (value.contains("premier")) return 0;
    if (value.contains("première")) return 0;

    if (value.contains("deuxième")) return 1;
    if (value.contains("second")) return 1;

    if (value.contains("troisième")) return 2;

    return null;
  }
}
