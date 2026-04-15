import 'dart:async';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../local/repositories.dart';
import '../remote/firebase_remote_data_source.dart';

class SyncService {
  SyncService({
    required SyncQueueRepository queueRepository,
    required RemoteDataSource remoteDataSource,
    required Connectivity connectivity,
    required String Function() organizationIdResolver,
  }) : _queueRepository = queueRepository,
       _remoteDataSource = remoteDataSource,
       _connectivity = connectivity,
       _resolveOrganizationId = organizationIdResolver;

  final SyncQueueRepository _queueRepository;
  final RemoteDataSource _remoteDataSource;
  final Connectivity _connectivity;
  final String Function() _resolveOrganizationId;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<int>? _pendingSub;
  Timer? _backoffTimer;
  bool _isFlushing = false;

  /// Start watching connectivity changes and auto-flush on restore.
  /// Also watches the pending queue so writes are flushed immediately.
  void startConnectivityWatch() {
    _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        flushPending();
      }
    });

    _pendingSub?.cancel();
    _pendingSub = _queueRepository.pendingCount().listen((count) {
      if (count > 0) flushPending();
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _pendingSub?.cancel();
    _backoffTimer?.cancel();
  }

  /// Process all pending sync queue items.
  Future<bool> flushPending() async {
    if (_isFlushing) return false;
    if (!_remoteDataSource.isAvailable) {
      dev.log(
        'flushPending atlandı: Firebase mevcut değil.',
        name: 'SyncService',
      );
      await _safeScheduleBackoffRetry();
      return false;
    }

    final connectivityResults = await _connectivity.checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      dev.log(
        'flushPending atlandı: internet bağlantısı yok.',
        name: 'SyncService',
      );
      await _safeScheduleBackoffRetry();
      return false;
    }

    _isFlushing = true;
    try {
      // Orphan (boş orgId'li) öğeleri mevcut bağlamla tamir et — aksi halde
      // sessizce yok sayılırsa veri kaybı olur.
      final currentOrgId = _resolveOrganizationId();
      if (currentOrgId.isNotEmpty) {
        final repaired = await _queueRepository.backfillOrgId(currentOrgId);
        if (repaired > 0) {
          dev.log(
            'SyncService: $repaired orphan kuyruk öğesi org=$currentOrgId ile tamir edildi.',
            name: 'SyncService',
          );
        }
      }

      final items = await _queueRepository.pendingItems();
      if (items.isEmpty) {
        dev.log(
          'flushPending: denenecek öğe yok.',
          name: 'SyncService',
        );
      } else {
        dev.log(
          'flushPending: ${items.length} öğe deneniyor.',
          name: 'SyncService',
        );
      }
      int successCount = 0;
      for (final item in items) {
        if (item.organizationId.isEmpty) {
          // Hâlâ orgId yoksa (kullanıcı henüz login olmamış) veri kaybolmasın
          // diye kalıcı hataya al; ileride elle inceleme mümkün kalsın.
          dev.log(
            'SyncService: orphan öğe terk ediliyor '
            '(${item.entityType}/${item.entityId}) — hiç orgId bulunamadı.',
            name: 'SyncService',
          );
          await _queueRepository.markAbandoned(item.id);
          continue;
        }

        try {
          final payload = _queueRepository.decodePayload(item.payload);

          if (item.action == 'delete') {
            final deletedAtStr =
                (payload['silinmeTarihi'] ?? payload['deletedAt']) as String?;
            final deletedBy =
                ((payload['sonDegistiren'] ?? payload['lastModifiedBy'])
                    as String?) ??
                '';
            final deviceId =
                ((payload['cihazId'] ?? payload['deviceId']) as String?) ?? '';
            final syncVersion =
                payload['senkronSurumu'] ?? payload['syncVersion'];
            await _remoteDataSource.softDelete(
              organizationId: item.organizationId,
              entityType: item.entityType,
              entityId: item.entityId,
              deletedAt: deletedAtStr != null
                  ? DateTime.parse(deletedAtStr)
                  : DateTime.now(),
              deletedBy: deletedBy,
              deviceId: deviceId,
              syncVersion: syncVersion is int
                  ? syncVersion
                  : int.tryParse(syncVersion?.toString() ?? ''),
            );
          } else {
            await _remoteDataSource.upsert(
              organizationId: item.organizationId,
              entityType: item.entityType,
              entityId: item.entityId,
              payload: payload,
            );
          }

          await _queueRepository.markSynced(item.id);
          successCount++;
        } catch (e, st) {
          dev.log(
            'SyncService flush hatası: ${item.entityType}/${item.entityId} '
            '(deneme ${item.retryCount + 1}): $e',
            name: 'SyncService',
            error: e,
            stackTrace: st,
          );
          await _queueRepository.markFailed(
            item.id,
            retryCount: item.retryCount + 1,
            error: e.toString(),
          );
        }
      }

      if (items.isNotEmpty) {
        dev.log(
          'flushPending tamamlandı: $successCount/${items.length} başarıyla senkronize edildi.',
          name: 'SyncService',
        );
      }
    } finally {
      _isFlushing = false;
    }

    // Backoff bekleyen item varsa, o zaman geldiğinde flush'ı tekrar tetikle.
    // Flush içinde exception olsa bile timer kurulur — aksi halde lost wakeup
    // oluşur ve backoff'a düşen item'lar bir daha denemeye giremez.
    await _safeScheduleBackoffRetry();
    return true;
  }

  /// Backoff scheduler'ı hata yutarak çağırır. flushPending'in tüm erken-return
  /// path'lerinden de güvenle tetiklenebilsin diye ayrı tutuldu.
  Future<void> _safeScheduleBackoffRetry() async {
    try {
      await _scheduleBackoffRetry();
    } catch (e, st) {
      dev.log(
        'backoff scheduler hatası: $e',
        name: 'SyncService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Backoff süresi dolan öğeler için otomatik retry planlar. pendingCount
  /// stream'i nextAttemptAt geçişini yakalamadığı için timer şart.
  Future<void> _scheduleBackoffRetry() async {
    _backoffTimer?.cancel();
    final nextAt = await _queueRepository.nextBackoffAt();
    if (nextAt == null) return;
    final delay = nextAt.difference(DateTime.now());
    if (delay.isNegative) {
      flushPending();
      return;
    }
    _backoffTimer = Timer(delay, flushPending);
  }
}
