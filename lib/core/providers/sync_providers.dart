import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/repositories.dart';
import '../../data/remote/firebase_remote_data_source.dart';
import '../../data/sync/bootstrap_service.dart';
import '../../data/sync/pull_sync_service.dart';
import '../../data/sync/sync_service.dart';
import 'database_providers.dart';
import 'preferences_providers.dart';

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return SyncQueueRepository(ref.watch(databaseProvider));
});

/// Kalıcı senkronizasyon hatasına düşen öğe sayısı — RootShell bu değeri
/// izleyip kullanıcıya uyarı banner'ı gösterir.
final failedPermanentCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncQueueRepositoryProvider).failedPermanentCount();
});

/// Henüz Firebase'e gönderilmemiş (pending) yerel değişiklik sayısı.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncQueueRepositoryProvider).pendingCount();
});

final remoteDataSourceProvider = Provider<RemoteDataSource>((ref) {
  return FirebaseRemoteDataSource();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    queueRepository: ref.watch(syncQueueRepositoryProvider),
    remoteDataSource: ref.watch(remoteDataSourceProvider),
    connectivity: ref.watch(connectivityProvider),
    // Resolver: her flush'ta canlı okunur — login sonrası orgId güncellendiğinde
    // SyncService yeniden oluşturulmaksızın doğru değer kullanılır.
    organizationIdResolver: () => ref.read(syncContextProvider).organizationId,
  );
});

/// Pull-sync akışında kalıcı `permission-denied` (yetki/kural/üyelik sorunu)
/// oluştuğunda dolan kullanıcıya gösterilecek mesaj; boşsa sorun yok. AuthGate
/// bunu izleyip sessiz retry döngüsü yerine "Organizasyon yüklenemedi" ekranına
/// düşer. Geçici ağ hataları buraya YAZILMAZ — yalnızca kalıcı yetki reddi.
final pullSyncFatalErrorProvider = StateProvider<String?>((ref) => null);

final pullSyncServiceProvider = Provider<PullSyncService>((ref) {
  final ctx = ref.watch(syncContextProvider);
  final service = PullSyncService(
    database: ref.watch(databaseProvider),
    deviceId: ctx.deviceId,
    onPermissionDenied: (_) {
      ref.read(pullSyncFatalErrorProvider.notifier).state =
          _kPullSyncPermissionMessage;
    },
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

const _kPullSyncPermissionMessage =
    'Sunucu, bu hesabın organizasyon verilerine erişimini reddetti '
    '(permission-denied). Genellikle kullanıcı kaydınızdaki "organizationId" '
    'eksik ya da yanlış olduğunda görülür. "Tekrar Dene" ile yeniden '
    'doğrulayın; sorun sürerse yöneticinizle iletişime geçin.';

final bootstrapServiceProvider = Provider<BootstrapService>((ref) {
  return BootstrapService(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(localPreferencesProvider),
  );
});
