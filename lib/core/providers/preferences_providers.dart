import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/local_preferences.dart';
import '../../data/sync/sync_context.dart';
import 'auth_providers.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main.dart with actual instance');
});

final localPreferencesProvider = Provider<LocalPreferences>((ref) {
  return LocalPreferences(ref.watch(sharedPreferencesProvider));
});

final syncContextProvider = Provider<SyncContext>((ref) {
  // authStateProvider'ı izle — login/logout olduğunda bu provider yeniden
  // hesaplanır ve prefs'teki güncel organizationId değerini alır.
  ref.watch(authStateProvider);
  final prefs = ref.watch(localPreferencesProvider);
  return SyncContext(
    userId: prefs.userId,
    deviceId: prefs.deviceId,
    organizationId: prefs.organizationId,
  );
});
