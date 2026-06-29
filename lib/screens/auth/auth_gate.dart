import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'auth_screen.dart';

class AuthGate extends StatelessWidget {
  final Widget Function(User user) builder;

  const AuthGate({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const AuthScreen();
        }

        return builder(user);
      },
    );
  }
}
