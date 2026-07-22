import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthenticated;

  const AuthScreen({
    super.key,
    this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isSignUp = true;
  bool loading = false;
  String errorMessage = "";

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String readableAuthError(Object error) {
    if (error is! FirebaseAuthException) {
      return "Connexion impossible. Réessaie dans quelques instants.";
    }

    switch (error.code) {
      case "email-already-in-use":
        return "Un compte existe déjà avec cet e-mail. Connecte-toi plutôt.";
      case "invalid-email":
        return "L’adresse e-mail n’est pas valide.";
      case "weak-password":
        return "Le mot de passe est trop faible. Utilise au moins 6 caractères.";
      case "user-not-found":
      case "wrong-password":
      case "invalid-credential":
        return "E-mail ou mot de passe incorrect.";
      case "network-request-failed":
        return "Connexion internet indisponible.";
      case "operation-not-allowed":
        return "Ce mode de connexion est temporairement indisponible.";
      default:
        return "Connexion impossible. Réessaie dans quelques instants.";
    }
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    try {
      if (isSignUp) {
        await AuthService.signUpWithEmail(
          email: emailController.text,
          password: passwordController.text,
        );
      } else {
        await AuthService.signInWithEmail(
          email: emailController.text,
          password: passwordController.text,
        );
      }

      widget.onAuthenticated?.call();

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = readableAuthError(error);
      });
    }

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  Future<void> resetPassword() async {
    if (emailController.text.trim().isEmpty) {
      setState(() {
        errorMessage = "Entre ton e-mail pour réinitialiser le mot de passe.";
      });
      return;
    }

    try {
      await AuthService.sendPasswordResetEmail(
        email: emailController.text,
      );

      if (!mounted) return;

      setState(() {
        errorMessage = "Un e-mail de réinitialisation a été envoyé.";
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = readableAuthError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F3),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Compte Zélia",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2F2523),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSignUp
                        ? "Crée ton compte pour sauvegarder ton espace personnel."
                        : "Connecte-toi pour retrouver ton espace personnel.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF7A6460),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: "E-mail",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: "Mot de passe",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF9A3D3D),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: loading ? null : submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE7B7AA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(
                      loading
                          ? "Chargement..."
                          : isSignUp
                              ? "Créer mon compte"
                              : "Me connecter",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            setState(() {
                              isSignUp = !isSignUp;
                              errorMessage = "";
                            });
                          },
                    child: Text(
                      isSignUp
                          ? "J’ai déjà un compte"
                          : "Créer un nouveau compte",
                    ),
                  ),
                  TextButton(
                    onPressed: loading ? null : resetPassword,
                    child: const Text("Mot de passe oublié"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
