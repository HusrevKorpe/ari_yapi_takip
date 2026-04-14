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
  }) : _queueRepository = queueRepository,
       _remoteDataSource = remoteDataSource,
       _connectivity = connectivity;

  final SyncQueueRepository _queueRepository;
  final RemoteDataSource _remoteDataSource;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<int>? _pendingSub;
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
  }

  /// Process all pending sync queue items.
  Future<bool> flushPending() async {
    if (_isFlushing) return false;
    if (!_remoteDataSource.isAvailable) return false;

    final connectivityResults = await _connectivity.checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      return false;
    }

    _isFlushing = true;
    try {
      final items = await _queueRepository.pendingItems();
      for (final item in items) {
        // orgId'siz öğeler auth öncesinden kalmıştır — senkronize edilemez, kuyruğu tıkamamaları için silinir.
        if (item.organizationId.isEmpty) {
          await _queueRepository.markSynced(item.id);
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
          );
        }
      }
    } finally {
      _isFlushing = false;
    }
    return true;
  }
}
