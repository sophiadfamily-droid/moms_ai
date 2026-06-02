import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';

class ChildrenScreen extends StatefulWidget {
  final Function(List<ChildProfile>) onNext;

  const ChildrenScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  final List<ChildProfile> children = [];

  final Color bg = const Color(0xFFF7EFEA);
  final Color accent = const Color(0xFFC78372);
  final Color textDark = const Color(0xFF3D241E);
  final Color textSoft = const Color(0xFF8B6F67);

  DateTime? parseFrenchDate(String value) {
    try {
      final clean = value.trim();

      final parts = clean.split("/");

      if (parts.length != 3) {
        return null;
      }

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      if (day < 1 || day > 31 || month < 1 || month > 12) {
        return null;
      }

      final date = DateTime(year, month, day);

      if (date.day != day || date.month != month || date.year != year) {
        return null;
      }

      if (date.isAfter(DateTime.now())) {
        return null;
      }

      return date;
    } catch (_) {
      return null;
    }
  }

  String formatFrenchDate(DateTime date) {
    final d = date.day.toString().padLeft(2, "0");
    final m = date.month.toString().padLeft(2, "0");
    final y = date.year.toString();

    return "$d/$m/$y";
  }

  String normalizeBirthDate(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return "";
    }

    final frenchDate = parseFrenchDate(clean);

    if (frenchDate != null) {
      return formatFrenchDate(frenchDate);
    }

    final isoDate = DateTime.tryParse(clean);

    if (isoDate != null) {
      return formatFrenchDate(isoDate);
    }

    return clean;
  }

  String calculateAge(String birthDateText) {
    final birthDate = parseFrenchDate(
      normalizeBirthDate(birthDateText),
    );

    if (birthDate == null) {
      return "";
    }

    final today = DateTime.now();

    var age = today.year - birthDate.year;

    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }

    return age.toString();
  }

  Future<String> pickDate({
    required String currentValue,
  }) async {
    final initialDate = parseFrenchDate(
          normalizeBirthDate(currentValue),
        ) ??
        DateTime(2021, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale("fr", "FR"),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: accent,
              onPrimary: Colors.white,
              surface: bg,
              onSurface: textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return normalizeBirthDate(currentValue);
    }

    return formatFrenchDate(picked);
  }

  Future<void> showChildSheet({
    ChildProfile? child,
    int? index,
  }) async {
    final nameController = TextEditingController(
      text: child?.firstName ?? "",
    );

    final birthDateController = TextEditingController(
      text: normalizeBirthDate(child?.birthDate ?? ""),
    );

    final classController = TextEditingController(
      text: child?.className ?? "",
    );

    String gender = child?.gender.isNotEmpty == true ? child!.gender : "Garçon";

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
              child: Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
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
                            color: textSoft.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        child == null
                            ? "Ajouter un enfant"
                            : "Modifier l'enfant",
                        style: GoogleFonts.playfairDisplay(
                          color: textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      buildTextField(
                        controller: nameController,
                        label: "Prénom",
                        hint: "Ex : Kasim",
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: buildTextField(
                              controller: birthDateController,
                              label: "Date de naissance",
                              hint: "JJ/MM/AAAA",
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(8),
                                FrenchDateInputFormatter(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () async {
                              final value = await pickDate(
                                currentValue: birthDateController.text.trim(),
                              );

                              setModalState(() {
                                birthDateController.text = value;
                              });
                            },
                            child: Container(
                              height: 62,
                              width: 62,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: accent.withOpacity(0.14),
                                ),
                              ),
                              child: Icon(
                                Icons.calendar_month_outlined,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        controller: classController,
                        label: "Classe",
                        hint: "Ex : Moyenne section",
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Genre",
                        style: GoogleFonts.nunito(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: ["Garçon", "Fille"].map((item) {
                          final selected = gender == item;

                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                gender = item;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent.withOpacity(0.16)
                                    : Colors.white.withOpacity(0.88),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? accent
                                      : accent.withOpacity(0.10),
                                ),
                              ),
                              child: Text(
                                item,
                                style: GoogleFonts.nunito(
                                  color: selected ? accent : textDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                "Annuler",
                                style: GoogleFonts.nunito(
                                  color: textSoft,
                                  fontWeight: FontWeight.w800,
                                ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              onPressed: () {
                                final name = nameController.text.trim();
                                final birth = normalizeBirthDate(
                                  birthDateController.text.trim(),
                                );

                                if (name.isEmpty) {
                                  return;
                                }

                                if (birth.isNotEmpty &&
                                    parseFrenchDate(birth) == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "La date doit être au format JJ/MM/AAAA",
                                      ),
                                    ),
                                  );

                                  return;
                                }

                                final updated = ChildProfile(
                                  firstName: name,
                                  age: calculateAge(birth),
                                  birthDate: birth,
                                  gender: gender,
                                  school: "",
                                  notes: child?.notes ?? "",
                                  photoPath: child?.photoPath ?? "",
                                  className: classController.text.trim(),
                                  allergies: child?.allergies ?? "",
                                  doctor: child?.doctor ?? "",
                                  medicalNotes: child?.medicalNotes ?? "",
                                  schoolTimeRanges:
                                      child?.schoolTimeRanges ?? [],
                                  activities: child?.activities ?? [],
                                );

                                setState(() {
                                  if (index != null) {
                                    children[index] = updated;
                                  } else {
                                    children.add(updated);
                                  }
                                });

                                Navigator.pop(context);
                              },
                              child: Text(
                                "Valider",
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withOpacity(0.14),
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.nunito(
            color: textSoft,
          ),
        ),
      ),
    );
  }

  void finish() {
    widget.onNext(children);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 8, 26, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "ZELIA",
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 34,
                  letterSpacing: 6,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 64),
              Text(
                "Ajoute tes\nenfants",
                style: GoogleFonts.playfairDisplay(
                  fontSize: 39,
                  height: 1.1,
                  color: textDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Zelia pourra mieux adapter ton planning familial.",
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  height: 1.5,
                  color: textSoft,
                ),
              ),
              const SizedBox(height: 26),
              ...children.asMap().entries.map((entry) {
                final index = entry.key;
                final child = entry.value;

                final cleanBirthDate = normalizeBirthDate(child.birthDate);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: accent.withOpacity(0.12),
                        child: Text(
                          child.firstName.isEmpty
                              ? "?"
                              : child.firstName[0].toUpperCase(),
                          style: GoogleFonts.nunito(
                            color: accent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              child.firstName,
                              style: GoogleFonts.nunito(
                                color: textDark,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              cleanBirthDate.isEmpty
                                  ? "Date de naissance non renseignée"
                                  : "${child.age.isEmpty ? "" : "${child.age} ans • "}né(e) le $cleanBirthDate",
                              style: GoogleFonts.nunito(
                                color: textSoft,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => showChildSheet(
                          child: child,
                          index: index,
                        ),
                        icon: Icon(
                          Icons.edit_outlined,
                          color: textSoft,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              GestureDetector(
                onTap: () => showChildSheet(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: accent.withOpacity(0.14),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: accent.withOpacity(0.12),
                        child: Icon(
                          Icons.add,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        "Ajouter un enfant",
                        style: GoogleFonts.nunito(
                          color: textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 38),
              GestureDetector(
                onTap: finish,
                child: Container(
                  height: 58,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      children.isEmpty ? "Continuer sans enfant" : "Terminer",
                      style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FrenchDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    var result = '';

    for (var i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) {
        result += '/';
      }

      result += digits[i];
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
