enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.uid,
    this.email,
    this.orgId,
    this.displayName,
  });

  final AuthStatus status;
  final String? uid;
  final String? email;
  final String? orgId;
  final String? displayName;

  static const unknown = AuthState(status: AuthStatus.unknown);
  static const unauthenticated = AuthState(status: AuthStatus.unauthenticated);

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
