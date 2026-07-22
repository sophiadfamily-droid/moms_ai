import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_anonymous_auth_bootstrap.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseAnonymousAuthBootstrap _anonymousBootstrap =
      FirebaseAnonymousAuthBootstrap(
    currentUid: () => _auth.currentUser?.uid,
    signInAnonymously: () async {
      final credential = await _auth.signInAnonymously();
      final uid = credential.user?.uid;
      if (uid == null || uid.trim().isEmpty) {
        throw const FirebaseAnonymousAuthException(
          'anonymous_auth_missing_uid',
        );
      }
      return uid;
    },
  );

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  static String? get currentUserId => _auth.currentUser?.uid;

  static bool get isLoggedIn => _auth.currentUser != null;

  static Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) {
    final normalizedEmail = email.trim();
    final current = _auth.currentUser;
    if (current?.isAnonymous ?? false) {
      return current!.linkWithCredential(
        EmailAuthProvider.credential(
          email: normalizedEmail,
          password: password,
        ),
      );
    }
    return _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
  }

  static Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> sendPasswordResetEmail({
    required String email,
  }) {
    return _auth.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  static Future<void> signOut() {
    return _auth.signOut();
  }

  static Future<String> ensureAuthenticatedUid() {
    return _anonymousBootstrap.ensureAuthenticatedUid();
  }

  static String requireUserId() {
    final uid = currentUserId;

    if (uid == null || uid.isEmpty) {
      throw StateError(
        "Aucun utilisateur connecté. Impossible d'accéder aux données Zélia.",
      );
    }

    return uid;
  }
}
