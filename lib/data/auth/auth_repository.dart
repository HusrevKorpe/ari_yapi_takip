import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'auth_state.dart';

class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth? _auth;

  bool get _isEnabled => _auth != null;

  String? get currentUid => _auth?.currentUser?.uid;

  Stream<AuthState> authStateChanges() {
    if (!_isEnabled) {
      // Firebase yoksa local-only modda oturum acik say
      return Stream.value(const AuthState(
        status: AuthStatus.authenticated,
        uid: 'local',
        displayName: 'Yerel Kullanici',
      ));
    }

    return _auth!.authStateChanges().map((user) {
      if (user == null) return AuthState.unauthenticated;
      return AuthState(
        status: AuthStatus.authenticated,
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      );
    });
  }

  /// Email ve sifre ile giris yapar. Firebase'de admin kullanicilari
  /// onceden Firebase Console'dan olusturulmalidir.
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (!_isEnabled) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'not-initialized',
        message: 'Firebase initialize edilmedi.',
      );
    }
    return _auth!.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth?.signOut();
  }
}
