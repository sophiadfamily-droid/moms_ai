import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/life_context/life_context_domains.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/services/life_context/life_context_adapter.dart';
import 'package:moms_ai/services/life_context/life_context_domain_adapters.dart';

void main() {
  final readAt = DateTime.utc(2026, 8, 21, 10);
  final request = LifeContextAdapterRequest(
    accountScopeId: 'account-a',
    readAt: readAt,
  );

  ShoppingItemModel item({
    required String id,
    required String title,
    required bool bought,
    bool urgent = false,
    String quantity = '',
    String notes = '',
    DateTime? createdAt,
  }) =>
      ShoppingItemModel(
        id: id,
        title: title,
        isBought: bought,
        createdAt: createdAt ?? DateTime.utc(2026, 8, 20, 9),
        isUrgent: urgent,
        quantity: quantity,
        notes: notes,
      );

  test('projects only active products with useful shopping details', () async {
    final section = await ShoppingLifeContextAdapter(
      load: (_) async => [
        item(id: 'bought', title: 'Pain', bought: true),
        item(
          id: 'normal',
          title: 'Lait',
          bought: false,
          quantity: '2 bouteilles',
          notes: 'Sans lactose',
        ),
        item(
          id: 'urgent',
          title: 'Fraises',
          bought: false,
          urgent: true,
          quantity: '500 g',
        ),
      ],
    ).load(request);

    expect(section.domain, LifeContextDomain.shopping);
    expect(section.metadata.source, LifeContextSourceKind.shoppingService);
    expect(section.metadata.itemCount, 2);
    expect(section.activeItems.map((value) => value.id), ['urgent', 'normal']);
    expect(section.activeItems.first.quantity, '500 g');
    expect(section.activeItems.last.notes, 'Sans lactose');
    expect(
      section.toJson().toString(),
      isNot(contains('bought')),
    );
  });

  test('empty active list stays distinct from bought history', () async {
    final section = await ShoppingLifeContextAdapter(
      load: (_) async => [item(id: 'bought', title: 'Pain', bought: true)],
    ).load(request);

    expect(section.metadata.availability, LifeContextAvailability.empty);
    expect(section.activeItems, isEmpty);
  });

  test('missing stable identity is reported as corrupted', () async {
    final section = await ShoppingLifeContextAdapter(
      load: (_) async => [
        ShoppingItemModel(
          title: 'Lait',
          isBought: false,
          createdAt: readAt,
        ),
      ],
    ).load(request);

    expect(section.metadata.availability, LifeContextAvailability.corrupted);
    expect(section.metadata.errorCode, 'invalid_shopping_domain');
  });
}
