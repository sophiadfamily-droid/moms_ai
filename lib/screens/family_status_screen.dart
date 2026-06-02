import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FamilyStatusScreen extends StatefulWidget {
  final Function(String) onNext;

  const FamilyStatusScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<FamilyStatusScreen> createState() => _FamilyStatusScreenState();
}

class _FamilyStatusScreenState extends State<FamilyStatusScreen> {
  String? selected;

  final List<String> choices = [
    "Je vis seule ",
    "Je vis avec mon partenaire ",
    "Nous sommes une famille avec enfants ",
    "Famille monoparentale ",
    "C'est un peu compliqué ",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7EFEA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "ZELIA",
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 34,
                  letterSpacing: 6,
                  color: const Color(0xFFC78372),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 70),
              Text(
                "À quoi ressemble\nton quotidien ?",
                style: GoogleFonts.playfairDisplay(
                  fontSize: 42,
                  height: 1.1,
                  color: const Color(0xFF3D241E),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Zelia s'adapte à ta vraie vie,\npas à une organisation parfaite.",
                style: GoogleFonts.nunito(
                  fontSize: 17,
                  height: 1.5,
                  color: const Color(0xFF8B6F67),
                ),
              ),
              const SizedBox(height: 34),
              ...choices.map((choice) {
                final isSelected = selected == choice;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selected = choice;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFC78372)
                          : Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFC78372)
                            : const Color(0xFFE8C7BD),
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: const Color(0xFFC78372).withOpacity(0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            choice,
                            style: GoogleFonts.nunito(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF3D241E),
                            ),
                          ),
                        ),
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFFC7A49A),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 26),
              GestureDetector(
                onTap: selected == null
                    ? null
                    : () {
                        widget.onNext(selected!);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 64,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: selected == null
                        ? const Color(0xFFE7D6D0)
                        : const Color(0xFFC78372),
                    borderRadius: BorderRadius.circular(34),
                    boxShadow: [
                      if (selected != null)
                        BoxShadow(
                          color: const Color(0xFFC78372).withOpacity(0.25),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      "Continuer",
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
