import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NameScreen extends StatefulWidget {
  final Function(String) onNext;

  const NameScreen({
    super.key,
    required this.onNext,
  });

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final TextEditingController controller = TextEditingController();

  void validate() {
    final value = controller.text.trim();
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
              color: const Color(0xFFC78372).withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Text(
            "Commencer",
            style: TextStyle(
              fontFamily: AppTheme.bodyFontFamily,
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "ZELIA",
                        style: TextStyle(
                          fontFamily: AppTheme.secondaryDisplayFontFamily,
                          fontSize: 34,
                          letterSpacing: 6,
                          color: const Color(0xFFC78372),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "Comment veux-tu\nque Zelia\nt’appelle ?",
                        style: TextStyle(
                          fontFamily: AppTheme.displayFontFamily,
                          fontSize: 38,
                          height: 1.1,
                          color: const Color(0xFF3D241E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Ton espace sera personnalisé\npour toi, avec douceur et simplicité.",
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFontFamily,
                          fontSize: 16,
                          height: 1.5,
                          color: const Color(0xFF8B6F67),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFE8C7BD),
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => validate(),
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF3D241E),
                          ),
                          decoration: InputDecoration(
                            hintText: "Nom d’affichage (facultatif)",
                            hintStyle: TextStyle(
                              fontFamily: AppTheme.bodyFontFamily,
                              color: const Color(0xFFB99B92),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => widget.onNext(''),
                          child: const Text('Je préfère compléter plus tard'),
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
