import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_repository.dart';
import '../../data/auth/auth_state.dart';
import '../../data/auth/organization_service.dart';
import 'database_providers.dart';
import 'preferences_providers.dart';

final firebaseAuthProvider = Provider<FirebaseAuth?>((ref) {
  return Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(firebaseAuthProvider));
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final organizationServiceProvider = Provider<OrganizationService>((ref) {
  return OrganizationService(
    ref.watch(localPreferencesProvider),
    ref.watch(databaseProvider),
  );
});
