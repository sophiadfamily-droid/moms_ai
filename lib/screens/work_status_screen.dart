import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WorkStatusScreen extends StatefulWidget {
  final Function(String) onNext;

  const WorkStatusScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<WorkStatusScreen> createState() => _WorkStatusScreenState();
}

class _WorkStatusScreenState extends State<WorkStatusScreen> {
  String selectedStatus = "";

  final List<String> statuses = [
    "Je suis maman au foyer ",
    "Je suis salariée ",
    "Je suis entrepreneuse ",
    "Je suis étudiante ",
    "Autre / recherche ",
  ];

  Widget buildChoice(String text) {
    final isSelected = selectedStatus == text;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedStatus = text;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 24,
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC78372) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFFE7CFC7),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF3D241E),
                ),
              ),
            ),
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : const Color(0xFFC7A79B),
                  width: 2,
                ),
                color: isSelected ? Colors.white : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 20,
                      color: Color(0xFFC78372),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EFEA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                "ZELIA",
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 34,
                  letterSpacing: 6,
                  color: const Color(0xFFC78372),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "Et dans ta\nvie pro ?",
                style: GoogleFonts.playfairDisplay(
                  fontSize: 52,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF3D241E),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Pour organiser tes journées selon ton rythme, ton énergie et tes priorités.",
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  height: 1.5,
                  color: const Color(0xFF9A847C),
                ),
              ),
              const SizedBox(height: 40),
              ...statuses.map((status) => buildChoice(status)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: selectedStatus.isEmpty
                      ? null
                      : () {
                          widget.onNext(selectedStatus);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC78372),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    "Continuer",
                    style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
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
