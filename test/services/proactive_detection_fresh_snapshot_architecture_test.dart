import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a domain change is invalidated before proactive detection reads it',
      () {
    final source = File('lib/services/proactive_detection_production.dart')
        .readAsStringSync();

    final eventInvalidation = source.indexOf(
      'case DetectionEvaluationTrigger.eventChanged:',
    );
    final taskInvalidation = source.indexOf(
      'case DetectionEvaluationTrigger.taskChanged:',
    );
    final routineInvalidation = source.indexOf(
      'case DetectionEvaluationTrigger.routineChanged:',
    );
    final explicitRefresh = source.indexOf(
      'case DetectionEvaluationTrigger.explicitInternalRefresh:',
    );
    final refresh = source.indexOf(
      'final snapshot = await lifeContext.refreshIfNeeded();',
    );

    expect(eventInvalidation, greaterThan(-1));
    expect(taskInvalidation, greaterThan(-1));
    expect(routineInvalidation, greaterThan(-1));
    expect(explicitRefresh, greaterThan(-1));
    expect(eventInvalidation, lessThan(refresh));
    expect(taskInvalidation, lessThan(refresh));
    expect(routineInvalidation, lessThan(refresh));
    expect(explicitRefresh, lessThan(refresh));
    expect(
      source,
      contains('lifeContext.invalidateSection(LifeContextDomain.event);'),
    );
    expect(
      source,
      contains('lifeContext.invalidateSection(LifeContextDomain.task);'),
    );
    expect(
      source,
      contains('lifeContext.invalidateSection(LifeContextDomain.routine);'),
    );
  });

  test('opening the attention center runs a fresh detection pass first', () {
    final source =
        File('lib/screens/daily_summary_screen.dart').readAsStringSync();

    final evaluate = source.indexOf(
      'NotificationService.evaluateDetections(',
    );
    final load = source.indexOf(
      'return NotificationService.loadDailySummary();',
    );

    expect(evaluate, greaterThan(-1));
    expect(load, greaterThan(evaluate));
    expect(
      source,
      contains('DetectionEvaluationTrigger.explicitInternalRefresh'),
    );
  });
}
