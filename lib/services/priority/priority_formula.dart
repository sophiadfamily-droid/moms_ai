import '../../models/priority/priority_models.dart';

abstract final class PriorityFormula {
  static const int version = 1;
  static const double minimumScore = 0;
  static const double maximumScore = 100;
  static const int maximumRankingSize = 100;
  static const int maximumDirectImpacts = 3;

  static const Map<PriorityDimension, double> weights = {
    PriorityDimension.urgency: .25,
    PriorityDimension.importance: .25,
    PriorityDimension.deadlinePressure: .25,
    PriorityDimension.effort: .05,
    PriorityDimension.flexibility: .10,
    PriorityDimension.directImpact: .10,
    PriorityDimension.dataQuality: .10,
  };

  static const Duration immediateWindow = Duration(hours: 2);
  static const Duration tomorrowWindow = Duration(days: 1);
  static const Duration threeDayWindow = Duration(days: 3);
  static const Duration sevenDayWindow = Duration(days: 7);

  static void validate() {
    const positiveDimensions = {
      PriorityDimension.urgency,
      PriorityDimension.importance,
      PriorityDimension.deadlinePressure,
      PriorityDimension.effort,
      PriorityDimension.flexibility,
      PriorityDimension.directImpact,
    };
    final positiveWeight = positiveDimensions.fold<double>(
      0,
      (sum, dimension) => sum + (weights[dimension] ?? 0),
    );
    if (weights.length != PriorityDimension.values.length ||
        weights.values.any((weight) => weight < 0 || weight > 1) ||
        (positiveWeight - 1).abs() > .000001 ||
        weights[PriorityDimension.dataQuality] != .10) {
      throw const PriorityException('invalid_priority_formula');
    }
  }
}
