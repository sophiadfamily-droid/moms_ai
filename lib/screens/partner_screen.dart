import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PartnerScreen extends StatefulWidget {
  final Function(String) onNext;

  const PartnerScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<PartnerScreen> createState() =>
      _PartnerScreenState();
}

class _PartnerScreenState
    extends State<PartnerScreen> {
  final TextEditingController controller =
      TextEditingController();

  void validate() {
    final value = controller.text.trim();

    if (value.isEmpty) return;

    widget.onNext(value);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget buildContinueButton() {
    return GestureDetector(
      onTap: validate,
      child: Container(
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFC78372),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC78372).withOpacity(0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            "Continuer",
            style: GoogleFonts.nunito(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7EFEA),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                26,
                8,
                26,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 26,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
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

                      const Spacer(),

                      Text(
                        "Comment s’appelle\nla personne qui\npartage ta vie ?",
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 38,
                          height: 1.1,
                          color: const Color(0xFF3D241E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        "Zelia pourra mieux comprendre\nvotre organisation familiale.",
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          height: 1.5,
                          color: const Color(0xFF8B6F67),
                        ),
                      ),

                      const SizedBox(height: 32),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFE8C7BD),
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => validate(),
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF3D241E),
                          ),
                          decoration: InputDecoration(
                            hintText: "Son prénom",
                            hintStyle: GoogleFonts.nunito(
                              color: const Color(0xFFB99B92),
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      const SizedBox(height: 18),

                      buildContinueButton(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

