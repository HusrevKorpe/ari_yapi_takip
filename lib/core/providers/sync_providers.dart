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
/// LiveList bu sayaçı kullanarak kullanıcı kaynaklı değişiklikleri uzaktan
/// gelen değişikliklerden ayırır: pending > 0 iken veri değişimi "yerel"
/// kabul edilip snapshot otomatik güncellenir, aksi halde banner gösterilir.
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

final pullSyncServiceProvider = Provider<PullSyncService>((ref) {
  final ctx = ref.watch(syncContextProvider);
  final service = PullSyncService(
    database: ref.watch(databaseProvider),
    deviceId: ctx.deviceId,
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final bootstrapServiceProvider = Provider<BootstrapService>((ref) {
  return BootstrapService(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(localPreferencesProvider),
  );
});
