import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shopping_item_model.dart';
import '../services/contextual_support_card_service.dart';
import '../services/shopping_service.dart';
import '../widgets/compact_contextual_support_card.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  List<ShoppingItemModel> items = [];
  bool loading = true;
  String selectedFilter = "À acheter";
  final Set<String> _recentlyCompletedItemKeys = <String>{};

  final Color bg = const Color(0xFFF8EFEA);
  final Color accent = const Color(0xFFE95D5D);
  final Color textDark = const Color(0xFF11181C);
  final Color textSoft = const Color(0xFF8B6F67);

  final List<String> filters = [
    "À acheter",
    "Urgent",
  ];

  final List<String> categories = [
    "Autre",
    "Boissons",
    "Frais",
    "Épicerie",
    "Maison",
    "Bébé",
    "Beauté",
    "Santé",
  ];

  final List<String> sections = [
    "Aujourd’hui",
    "Plus tard",
  ];

  @override
  void initState() {
    super.initState();
    ShoppingService.shoppingVersion.addListener(loadItems);
    loadItems();
  }

  @override
  void dispose() {
    ShoppingService.shoppingVersion.removeListener(loadItems);
    super.dispose();
  }

  Future<void> loadItems() async {
    final loadedItems = await ShoppingService.getItems();

    loadedItems.sort((a, b) {
      if (a.isBought != b.isBought) return a.isBought ? 1 : -1;
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    if (!mounted) return;

    setState(() {
      items = loadedItems;
      loading = false;
    });
  }

  Future<void> saveCurrentItems() async {
    await ShoppingService.updateItems(items);
  }

  List<ShoppingItemModel> get toBuyItems {
    return items.where((item) => !item.isBought).toList();
  }

  List<ShoppingItemModel> get urgentItems {
    return items.where((item) => !item.isBought && item.isUrgent).toList();
  }

  int indexOfItem(ShoppingItemModel item) {
    return items.indexWhere(
      (current) => ShoppingService.areSameShoppingItem(current, item),
    );
  }

  Future<void> toggleItem(ShoppingItemModel item) async {
    final index = indexOfItem(item);
    if (index == -1) return;

    final itemKey = _itemVisualKey(item);
    final willBeBought = !item.isBought;
    setState(() {
      if (willBeBought) {
        _recentlyCompletedItemKeys.add(itemKey);
      } else {
        _recentlyCompletedItemKeys.remove(itemKey);
      }
      items[index] = item.copyWith(isBought: willBeBought);
    });
    if (!willBeBought) return;
    await Future<void>.delayed(const Duration(milliseconds: 750));
    final completedIndex = items.indexWhere(
      (current) => _itemVisualKey(current) == itemKey && current.isBought,
    );
    if (completedIndex == -1) return;
    items.removeAt(completedIndex);
    _recentlyCompletedItemKeys.remove(itemKey);
    await ShoppingService.updateItems(items);
    if (mounted) setState(() {});
  }

  String _itemVisualKey(ShoppingItemModel item) {
    return item.id ?? '${item.title}-${item.createdAt.toIso8601String()}';
  }

  Future<void> toggleUrgent(ShoppingItemModel item) async {
    final index = indexOfItem(item);
    if (index == -1) return;

    items[index] = item.copyWith(isUrgent: !item.isUrgent);
    await ShoppingService.updateItems(items);
  }

  Future<void> deleteItem(ShoppingItemModel item) async {
    items.removeWhere(
      (current) => ShoppingService.areSameShoppingItem(current, item),
    );
    await saveCurrentItems();
  }

  Future<void> clearToBuy() async {
    items.clear();
    await saveCurrentItems();
  }

  String autoCategory(String title) {
    final value = title.toLowerCase();

    if (value.contains("eau") ||
        value.contains("lait") ||
        value.contains("jus") ||
        value.contains("coca")) {
      return "Boissons";
    }

    if (value.contains("pain") ||
        value.contains("pâte") ||
        value.contains("pates") ||
        value.contains("riz") ||
        value.contains("farine")) {
      return "Épicerie";
    }

    if (value.contains("shampo") ||
        value.contains("lessive") ||
        value.contains("savon") ||
        value.contains("gel douche")) {
      return "Beauté";
    }

    if (value.contains("couche") ||
        value.contains("lingette") ||
        value.contains("biberon")) {
      return "Bébé";
    }

    if (value.contains("pq") ||
        value.contains("papier") ||
        value.contains("sopalin")) {
      return "Maison";
    }

    if (value.contains("banane") ||
        value.contains("pomme") ||
        value.contains("œuf") ||
        value.contains("oeuf") ||
        value.contains("beurre") ||
        value.contains("fromage")) {
      return "Frais";
    }

    if (value.contains("doliprane") ||
        value.contains("médicament") ||
        value.contains("medicament")) {
      return "Santé";
    }

    return "Autre";
  }

  IconData iconForCategory(String category) {
    switch (category) {
      case "Boissons":
        return Icons.water_drop_outlined;
      case "Frais":
        return Icons.egg_alt_outlined;
      case "Maison":
        return Icons.cleaning_services_outlined;
      case "Épicerie":
        return Icons.breakfast_dining_outlined;
      case "Bébé":
        return Icons.child_care_outlined;
      case "Beauté":
        return Icons.spa_outlined;
      case "Santé":
        return Icons.medical_services_outlined;
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  List<ShoppingItemModel> filteredItems() {
    return items.where((item) {
      final remainsVisible = !item.isBought ||
          _recentlyCompletedItemKeys.contains(_itemVisualKey(item));
      if (!remainsVisible) return false;
      if (selectedFilter == "Urgent") return item.isUrgent;
      return true;
    }).toList();
  }

  Map<String, List<ShoppingItemModel>> groupedByCategory(
    List<ShoppingItemModel> list,
  ) {
    final grouped = <String, List<ShoppingItemModel>>{};
    for (final item in list) {
      grouped.putIfAbsent(item.category, () => []);
      grouped[item.category]!.add(item);
    }
    return grouped;
  }

  Map<String, List<ShoppingItemModel>> groupedBySection(
    List<ShoppingItemModel> list,
  ) {
    final grouped = <String, List<ShoppingItemModel>>{};
    for (final item in list) {
      final section =
          sections.contains(item.section) ? item.section : "Aujourd’hui";
      grouped.putIfAbsent(section, () => []);
      grouped[section]!.add(item);
    }
    return grouped;
  }

  Future<void> showShoppingSheet({
    ShoppingItemModel? item,
  }) async {
    final isEdit = item != null;
    final titleController = TextEditingController(text: item?.title ?? "");
    final notesController = TextEditingController(text: item?.notes ?? "");

    String category =
        item?.category.isNotEmpty == true ? item!.category : "Autre";
    String section =
        item?.section.isNotEmpty == true ? item!.section : "Aujourd’hui";
    bool urgent = item?.isUrgent ?? false;

    if (!sections.contains(section)) section = "Aujourd’hui";

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottom = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: buildSheetContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSheetHandle(),
                    const SizedBox(height: 18),
                    buildSheetTitle(
                        isEdit ? "Modifier l’article" : "Nouvel article"),
                    const SizedBox(height: 18),
                    buildSheetTextField(
                      controller: titleController,
                      label: "Article",
                      hint: "Ex : Eau, lait, couches...",
                      onChanged: (value) {
                        if (!isEdit) {
                          setModalState(() {
                            category = autoCategory(value);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    buildSheetTextField(
                      controller: notesController,
                      label: "Notes",
                      hint: "Marque, détail, préférence...",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 18),
                    buildChoiceSection(
                      title: "Quand l’acheter ?",
                      items: sections,
                      selected: section,
                      onTap: (value) => setModalState(() => section = value),
                    ),
                    const SizedBox(height: 16),
                    buildChoiceSection(
                      title: "Catégorie",
                      items: categories,
                      selected: category,
                      iconBuilder: iconForCategory,
                      onTap: (value) => setModalState(() => category = value),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => setModalState(() => urgent = !urgent),
                      child: buildPremiumToggle(
                        icon: Icons.priority_high_rounded,
                        title: "Marquer comme urgent",
                        active: urgent,
                      ),
                    ),
                    const SizedBox(height: 22),
                    buildSheetActions(
                      isEdit: isEdit,
                      onSave: () async {
                        await HapticFeedback.lightImpact();
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;

                        final updated = item?.copyWith(
                              title: title,
                              category: category,
                              notes: notesController.text.trim(),
                              isUrgent: urgent,
                              section: section,
                            ) ??
                            ShoppingItemModel(
                              title: title,
                              isBought: false,
                              createdAt: DateTime.now(),
                              category: category,
                              notes: notesController.text.trim(),
                              isUrgent: urgent,
                              section: section,
                            );

                        if (isEdit) {
                          final index = indexOfItem(item);
                          if (index != -1) {
                            items[index] = updated;
                            await ShoppingService.updateItems(items);
                          }
                        } else {
                          await ShoppingService.addItem(updated);
                        }

                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildSheetContainer({required Widget child}) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: SingleChildScrollView(child: child),
    );
  }

  Widget buildSheetHandle() {
    return Center(
      child: Container(
        width: 46,
        height: 5,
        decoration: BoxDecoration(
          color: textSoft.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }

  Widget buildSheetTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w900,
        color: textDark,
      ),
    );
  }

  Widget buildSheetActions({
    required bool isEdit,
    required Future<void> Function() onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Annuler",
              style: TextStyle(color: textSoft, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: onSave,
            child: Text(
              isEdit ? "Enregistrer" : "Ajouter",
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildSheetTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.10)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: TextStyle(color: textSoft),
          hintText: hint,
        ),
      ),
    );
  }

  Widget buildChoiceSection({
    required String title,
    required List<String> items,
    required String selected,
    required Function(String) onTap,
    IconData Function(String)? iconBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(color: textDark, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final isSelected = selected == item;
            return GestureDetector(
              onTap: () => onTap(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color:
                          isSelected ? accent : accent.withValues(alpha: 0.10)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (iconBuilder != null) ...[
                      Icon(iconBuilder(item),
                          size: 17, color: isSelected ? accent : textSoft),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      item,
                      style: TextStyle(
                        color: isSelected ? accent : textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget buildPremiumToggle({
    required IconData icon,
    required String title,
    required bool active,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: active
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: active
                ? accent.withValues(alpha: 0.55)
                : accent.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: active ? accent : textSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: textDark, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Liste de courses",
              style: TextStyle(
                color: textDark,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          CircleAvatar(
            radius: 28,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: IconButton(
              onPressed: () => showShoppingSheet(),
              icon: Icon(Icons.add, color: accent, size: 31),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDashboardSummary() {
    final toBuy = toBuyItems.length;
    final urgent = urgentItems.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(
              child: Text(
                "$toBuy",
                style: TextStyle(
                    color: accent, fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toBuy == 0
                      ? "Liste vide pour le moment"
                      : "$toBuy produit(s) à acheter",
                  style: TextStyle(
                      color: textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  urgent == 0
                      ? "Aucun produit urgent"
                      : "$urgent produit(s) urgent(s)",
                  style: TextStyle(
                      color: textSoft,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSmartShoppingCard() {
    final supportMessage = const ContextualSupportCardService().forShopping(
      pendingCount: toBuyItems.length,
      boughtCount: 0,
      urgentCount: urgentItems.length,
      urgentItemTitle: urgentItems.isEmpty ? null : urgentItems.first.title,
      now: DateTime.now(),
    );

    return CompactContextualSupportCard(
      key: const Key('shopping-contextual-support-card'),
      supportMessage: supportMessage,
      accent: accent,
      textColor: textDark,
      secondaryTextColor: textSoft,
    );
  }

  Widget buildFilters() {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = selectedFilter == filter;
          return GestureDetector(
            onTap: () => setState(() => selectedFilter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.86)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(28),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    color: selected ? Colors.white : textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: filters.length,
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 14),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
                color: textDark, fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 12),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.85), shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Widget buildShoppingSection(List<ShoppingItemModel> sectionItems) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(34),
      ),
      child: Column(
        children: [
          ...sectionItems.map((item) {
            final index = sectionItems.indexOf(item);
            final isLast = index == sectionItems.length - 1;
            return Column(
              children: [
                Dismissible(
                  key: ValueKey(
                    item.id ??
                        "${item.title}-${item.createdAt.toIso8601String()}",
                  ),
                  direction: DismissDirection.horizontal,
                  background: buildSwipeBackground(
                    icon: Icons.check_rounded,
                    label: "Acheté",
                    alignLeft: true,
                  ),
                  secondaryBackground: buildSwipeBackground(
                    icon: Icons.delete_outline,
                    label: "Supprimer",
                    alignLeft: false,
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      await HapticFeedback.lightImpact();
                      await toggleItem(item);
                      return false;
                    }
                    await HapticFeedback.lightImpact();
                    await deleteItem(item);
                    return true;
                  },
                  child: buildShoppingRow(item),
                ),
                if (!isLast)
                  Divider(height: 1, color: accent.withValues(alpha: 0.08)),
              ],
            );
          }),
          buildDeleteSectionRow(),
        ],
      ),
    );
  }

  Widget buildSwipeBackground({
    required IconData icon,
    required String label,
    required bool alignLeft,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding:
          EdgeInsets.only(left: alignLeft ? 18 : 0, right: alignLeft ? 0 : 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment:
            alignLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Future<void> showShoppingOptions(ShoppingItemModel item) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSheetHandle(),
                const SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: accent),
                  title: const Text("Modifier"),
                  onTap: () {
                    Navigator.pop(context);
                    showShoppingSheet(item: item);
                  },
                ),
                ListTile(
                  leading: Icon(
                    item.isUrgent
                        ? Icons.priority_high_rounded
                        : Icons.priority_high_outlined,
                    color: accent,
                  ),
                  title: Text(
                      item.isUrgent ? "Retirer l’urgence" : "Marquer urgent"),
                  onTap: () async {
                    Navigator.pop(context);
                    await toggleUrgent(item);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: accent),
                  title: Text(
                    "Supprimer",
                    style:
                        TextStyle(color: accent, fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await deleteItem(item);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildShoppingRow(ShoppingItemModel item) {
    final subtitleParts = [
      if (item.notes.trim().isNotEmpty) item.notes,
    ];

    return GestureDetector(
      onTap: () => toggleItem(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            buildCheckCircle(
              key: Key('shopping-check-${_itemVisualKey(item)}'),
              checked: item.isBought,
              onTap: () => toggleItem(item),
            ),
            const SizedBox(width: 16),
            CircleAvatar(
              radius: 24,
              backgroundColor: accent.withValues(alpha: 0.08),
              child: Icon(iconForCategory(item.category),
                  color: accent.withValues(alpha: 0.78), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: () => showShoppingSheet(item: item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: item.isBought
                                  ? textSoft.withValues(alpha: 0.65)
                                  : textDark,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              decoration: item.isBought
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (item.isUrgent) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.priority_high_rounded,
                              color: accent, size: 20),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        buildTag(item.category),
                        buildTag(sections.contains(item.section)
                            ? item.section
                            : "Aujourd’hui"),
                        if (subtitleParts.isNotEmpty)
                          buildTag(subtitleParts.first),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: () => showShoppingOptions(item),
              icon: Icon(Icons.more_horiz, color: textSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTag(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        value,
        style: TextStyle(
            color: textSoft, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget buildDeleteSectionRow() {
    return GestureDetector(
      onTap: () async {
        await clearToBuy();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: accent.withValues(alpha: 0.08),
              child: Icon(Icons.delete_outline, color: accent, size: 27),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                "Supprimer la section",
                style: TextStyle(
                    color: accent, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            Icon(Icons.chevron_right, color: textSoft),
          ],
        ),
      ),
    );
  }

  Widget buildCheckCircle({
    Key? key,
    required bool checked,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 27,
        height: 27,
        decoration: BoxDecoration(
          color: checked ? accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
              color: checked ? accent : accent.withValues(alpha: 0.62),
              width: 1.8),
        ),
        child: checked
            ? const Icon(Icons.check, color: Colors.white, size: 17)
            : null,
      ),
    );
  }

  Widget buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 60, 34, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shopping_bag_outlined,
              color: accent.withValues(alpha: 0.45), size: 54),
          const SizedBox(height: 16),
          Text(
            "Ta liste de courses est vide 💕",
            style: TextStyle(
                color: textSoft, fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget buildGroupedContent() {
    final list = filteredItems();
    if (list.isEmpty) return buildEmptyState();

    final grouped = groupedBySection(list);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSectionTitle(entry.key),
            buildShoppingSection(entry.value),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : SafeArea(
              child: RefreshIndicator(
                color: accent,
                onRefresh: loadItems,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildHeader(),
                      buildDashboardSummary(),
                      buildSmartShoppingCard(),
                      buildFilters(),
                      buildGroupedContent(),
                      const SizedBox(height: 110),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
