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

  Future<bool> flushPending() async {
    final connectivityResults = await _connectivity.checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none)) {
      return false;
    }

    final items = await _queueRepository.pendingItems();
    for (final item in items) {
      try {
        final payload = _queueRepository.decodePayload(item.payload);
        await _remoteDataSource.upsert(
          entityType: item.entityType,
          entityId: item.entityId,
          action: item.action,
          payload: payload,
        );
        await _queueRepository.markSynced(item.id);
      } catch (_) {
        await _queueRepository.markFailed(
          item.id,
          retryCount: item.retryCount + 1,
        );
      }
    }

    return true;
  }
}
