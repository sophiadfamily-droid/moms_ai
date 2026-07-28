import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/services/action_handler_service.dart';
import 'package:moms_ai/services/cloud_shopping_service.dart';
import 'package:moms_ai/services/shopping_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_entity_id_generator.dart';

void main() {
  ShoppingItemModel buildItem({
    String? id,
    String title = 'Lait',
    DateTime? createdAt,
  }) {
    return ShoppingItemModel(
      id: id,
      title: title,
      isBought: false,
      createdAt: createdAt ?? DateTime(2026, 7, 20, 9, 30),
      category: 'Frais',
      notes: 'Deux bouteilles, magasin du quartier',
      isUrgent: true,
      section: 'Aujourd’hui',
    );
  }

  group('ShoppingItemModel stable identity', () {
    test('copyWith preserves ID across all editable business fields', () {
      final item = buildItem(id: 'shopping-1');

      final updated = item.copyWith(
        title: 'Lait entier x3',
        category: 'Autre',
        notes: 'Trois bouteilles, autre magasin',
        isBought: true,
        isUrgent: false,
        section: 'Plus tard',
      );

      expect(updated.id, 'shopping-1');
      expect(updated.title, 'Lait entier x3');
      expect(updated.category, 'Autre');
      expect(updated.notes, 'Trois bouteilles, autre magasin');
      expect(updated.isBought, isTrue);
      expect(updated.isUrgent, isFalse);
      expect(updated.section, 'Plus tard');
    });

    test('JSON round trip preserves an existing ID', () {
      final item = buildItem(id: 'shopping-1');

      expect(item.toJson()['id'], 'shopping-1');
      expect(ShoppingItemModel.fromJson(item.toJson()).id, 'shopping-1');
    });

    test('legacy JSON remains readable without inventing an ID', () {
      final json = buildItem().toJson();
      final restored = ShoppingItemModel.fromJson(json);

      expect(json, isNot(containsPair('id', anything)));
      expect(restored.id, isNull);
      expect(restored.title, 'Lait');
    });

    test('a newly constructed non-persisted item has no identity', () {
      final proposal = buildItem();

      expect(proposal.id, isNull);
    });
  });

  group('ShoppingService identity comparison', () {
    test('same valid IDs identify the same edited item', () {
      final item = buildItem(id: 'shopping-1');
      final edited = item.copyWith(title: 'Nouveau nom');

      expect(ShoppingService.areSameShoppingItem(item, edited), isTrue);
    });

    test('different valid IDs override identical legacy properties', () {
      final first = buildItem(id: 'shopping-1');
      final second = buildItem(id: 'shopping-2');

      expect(ShoppingService.areSameShoppingItem(first, second), isFalse);
    });

    test('legacy fallback keeps exact title and createdAt comparison', () {
      final first = buildItem();
      final sameLegacyItem = buildItem();
      final renamed = buildItem(title: 'Pain');
      final recreated = buildItem(createdAt: DateTime(2026, 7, 20, 9, 31));

      expect(
          ShoppingService.areSameShoppingItem(first, sameLegacyItem), isTrue);
      expect(ShoppingService.areSameShoppingItem(first, renamed), isFalse);
      expect(ShoppingService.areSameShoppingItem(first, recreated), isFalse);
    });

    test('ID-first list operations target only the selected item', () {
      final selected = buildItem(id: 'shopping-1');
      final duplicate = buildItem(id: 'shopping-2');
      final items = [selected, duplicate];

      final index = items.indexWhere(
        (item) => ShoppingService.areSameShoppingItem(item, selected),
      );
      items[index] = items[index].copyWith(isBought: true);

      expect(items.first.id, 'shopping-1');
      expect(items.first.isBought, isTrue);
      expect(items.last.isBought, isFalse);

      items.removeWhere(
        (item) => ShoppingService.areSameShoppingItem(item, selected),
      );
      expect(items, [same(duplicate)]);
    });
  });

  group('ShoppingService creation identity', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates exactly one ID at the persistence boundary', () async {
      final generator = FakeEntityIdGenerator(['shopping-generated']);

      await ShoppingService.addItem(buildItem(), idGenerator: generator);

      final stored = await _storedItems();
      expect(generator.callCount, 1);
      expect(stored.single.id, 'shopping-generated');
    });

    test('preserves a valid ID without calling the generator', () async {
      final generator = FakeEntityIdGenerator(['unused']);

      await ShoppingService.addItem(
        buildItem(id: 'shopping-existing'),
        idGenerator: generator,
      );

      final stored = await _storedItems();
      expect(generator.callCount, 0);
      expect(stored.single.id, 'shopping-existing');
    });

    test('replaces empty and whitespace IDs exactly once each', () async {
      final generator = FakeEntityIdGenerator(['from-empty', 'from-blank']);

      await ShoppingService.addItem(
        buildItem(id: ''),
        idGenerator: generator,
      );
      await ShoppingService.addItem(
        buildItem(id: '   ', title: 'Pain'),
        idGenerator: generator,
      );

      final stored = await _storedItems();
      expect(generator.callCount, 2);
      expect(stored.map((item) => item.id).toSet(), {
        'from-empty',
        'from-blank',
      });
    });

    test('SharedPreferences preserves IDs and legacy null IDs', () async {
      await ShoppingService.saveItems([
        buildItem(id: 'shopping-local'),
        buildItem(title: 'Legacy'),
      ]);

      final stored = await _storedItems();
      expect(stored.first.id, 'shopping-local');
      expect(stored.last.id, isNull);
    });

    test('chat creation persists an identified shopping item', () async {
      await ActionHandlerService.handleAction(
        action: {'type': 'shopping', 'title': 'Pommes'},
        currentUserMessage: 'Ajoute des pommes aux courses',
        normalizeTime: (value) => value,
        parseDurationMinutes: (value) => 0,
        weekdayFromText: () => 0,
        messageLooksRecurringWeekly: () => false,
        nextDateForWeekday: (weekday) => '',
        eventNeedsTravel: (action) => false,
        buildStartDateTimeIso: ({required date, required time}) => '',
        buildEndDateTimeIso: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '',
        endTimeFromDuration: ({
          required date,
          required time,
          required durationMinutes,
        }) =>
            '',
      );

      final stored = await _storedItems();
      expect(stored.single.title, 'Pommes');
      expect(stored.single.id, isNotNull);
      expect(stored.single.id, isNotEmpty);
    });

    test('confirmed grouped action is idempotent across a double retry',
        () async {
      Future<void> execute() async {
        await ActionHandlerService.handleAction(
          action: const {
            'type': 'shopping',
            'actionId': 'shopping-confirmation',
            'title': 'Lait',
            'items': ['Lait', 'Bananes'],
          },
          currentUserMessage: 'Il manque du lait et des bananes',
          normalizeTime: (value) => value,
          parseDurationMinutes: (value) => 0,
          weekdayFromText: () => 0,
          messageLooksRecurringWeekly: () => false,
          nextDateForWeekday: (weekday) => '',
          eventNeedsTravel: (action) => false,
          buildStartDateTimeIso: ({required date, required time}) => '',
          buildEndDateTimeIso: ({
            required date,
            required time,
            required durationMinutes,
          }) =>
              '',
          endTimeFromDuration: ({
            required date,
            required time,
            required durationMinutes,
          }) =>
              '',
        );
      }

      await execute();
      await execute();

      final stored = await _storedItems();
      expect(stored.map((item) => item.title), ['Lait', 'Bananes']);
      expect(stored.map((item) => item.id), [
        'shopping-confirmation:0',
        'shopping-confirmation:1',
      ]);
    });
  });

  group('CloudShoppingService identity compatibility', () {
    test('Firestore loading injects the document ID', () {
      final item = CloudShoppingService.shoppingItemFromDocument(
        documentId: 'firestore-shopping-id',
        data: buildItem().toJson(),
      );

      expect(item.id, 'firestore-shopping-id');
    });

    test('valid ID selects the document and stays out of cloud data', () {
      final item = buildItem(id: 'shopping-1');
      final expectedPayload = Map<String, dynamic>.from(item.toJson())
        ..remove('id');

      expect(
        CloudShoppingService.documentIdForShoppingItem(item),
        'shopping-1',
      );
      expect(
        CloudShoppingService.firestoreDataForShoppingItem(item),
        expectedPayload,
      );
      expect(
        CloudShoppingService.firestoreDataForShoppingItem(item),
        isNot(containsPair('id', anything)),
      );
    });

    test('missing, empty and whitespace IDs use the exact legacy hash', () {
      final item = buildItem();
      final raw = [
        item.createdAt.toIso8601String(),
        item.title,
        item.category,
      ].join('|');
      final legacyId = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

      expect(CloudShoppingService.documentIdForShoppingItem(item), legacyId);
      expect(
        CloudShoppingService.documentIdForShoppingItem(item.copyWith(id: '')),
        legacyId,
      );
      expect(
        CloudShoppingService.documentIdForShoppingItem(
          item.copyWith(id: '   '),
        ),
        legacyId,
      );
    });
  });
}

Future<List<ShoppingItemModel>> _storedItems() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList(ShoppingService.shoppingKey) ?? const [];
  return stored
      .map(
        (item) => ShoppingItemModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(item) as Map),
        ),
      )
      .toList();
}
