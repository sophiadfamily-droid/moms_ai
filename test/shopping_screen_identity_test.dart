import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moms_ai/models/shopping_item_model.dart';
import 'package:moms_ai/screens/shopping_screen.dart';
import 'package:moms_ai/services/shopping_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('interface creation persists a shopping item with an ID',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: ShoppingScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(_articleField, 'Pommes interface');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(ElevatedButton, 'Ajouter');
    await tester.ensureVisible(addButton);
    tester.widget<ElevatedButton>(addButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedItems();
    expect(stored, hasLength(1));
    expect(stored.single.title, 'Pommes interface');
    expect(stored.single.id, isNotNull);
    expect(stored.single.id, isNotEmpty);
  });

  testWidgets('interface editing preserves the shopping item ID',
      (tester) async {
    final item = ShoppingItemModel(
      id: 'shopping-interface',
      title: 'Pommes initiales',
      isBought: false,
      createdAt: DateTime(2026, 7, 20),
    );
    SharedPreferences.setMockInitialValues({
      ShoppingService.shoppingKey: [jsonEncode(item.toJson())],
    });

    await tester.pumpWidget(
      const MaterialApp(home: ShoppingScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pommes initiales'));
    await tester.pumpAndSettle();

    await tester.enterText(_articleField, 'Pommes modifiées');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(ElevatedButton, 'Enregistrer');
    await tester.ensureVisible(saveButton);
    tester.widget<ElevatedButton>(saveButton).onPressed!();
    await tester.pumpAndSettle();

    final stored = await _storedItems();
    expect(stored, hasLength(1));
    expect(stored.single.title, 'Pommes modifiées');
    expect(stored.single.id, 'shopping-interface');
  });

  testWidgets('empty shopping list keeps a positive contextual card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: ShoppingScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shopping-contextual-support-card')),
      findsOneWidget,
    );
    expect(find.text('Courses intelligentes'), findsNothing);
    expect(find.textContaining('produit(s)'), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(const Key('shopping-contextual-support-card')),
          )
          .height,
      106,
    );
  });

  testWidgets('urgent shopping evidence stays visible in the compact card',
      (tester) async {
    final urgent = ShoppingItemModel(
      id: 'urgent-shopping-item',
      title: 'Lait',
      isBought: false,
      isUrgent: true,
      createdAt: DateTime(2026, 8, 18),
    );
    SharedPreferences.setMockInitialValues({
      ShoppingService.shoppingKey: [jsonEncode(urgent.toJson())],
    });

    await tester.pumpWidget(
      const MaterialApp(home: ShoppingScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('À ne pas oublier'), findsOneWidget);
    expect(
      find.text('Pense à acheter « Lait » en priorité.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
  });

  testWidgets('urgent shopping card is informative and does not filter',
      (tester) async {
    final urgent = ShoppingItemModel(
      id: 'urgent-shopping-item',
      title: 'Lait',
      isBought: false,
      isUrgent: true,
      createdAt: DateTime(2026, 8, 18),
    );
    final ordinary = ShoppingItemModel(
      id: 'ordinary-shopping-item',
      title: 'Pain',
      isBought: false,
      createdAt: DateTime(2026, 8, 18),
    );
    SharedPreferences.setMockInitialValues({
      ShoppingService.shoppingKey: [
        jsonEncode(urgent.toJson()),
        jsonEncode(ordinary.toJson()),
      ],
    });

    await tester.pumpWidget(
      const MaterialApp(home: ShoppingScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lait'), findsOneWidget);
    expect(find.text('Pain'), findsOneWidget);
    expect(find.text('Catégories'), findsNothing);
    expect(find.text('Organisation'), findsNothing);
    expect(find.text('Acheté'), findsNothing);

    await tester.tap(
      find.byKey(const Key('shopping-contextual-support-card')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lait'), findsOneWidget);
    expect(find.text('Pain'), findsOneWidget);
  });

  testWidgets('checking an item shows completion before removing its row',
      (tester) async {
    final item = ShoppingItemModel(
      id: 'shopping-check-feedback',
      title: 'Kiwis',
      isBought: false,
      createdAt: DateTime(2026, 8, 18),
    );
    SharedPreferences.setMockInitialValues({
      ShoppingService.shoppingKey: [jsonEncode(item.toJson())],
    });

    await tester.pumpWidget(
      const MaterialApp(home: ShoppingScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('shopping-check-shopping-check-feedback')),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Kiwis'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Kiwis'), findsNothing);
  });
}

final Finder _articleField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Article',
);

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
