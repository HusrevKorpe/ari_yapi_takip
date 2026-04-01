import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../data/local/repositories.dart';
import '../data/remote/firebase_remote_data_source.dart';
import '../data/sync/sync_service.dart';

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

final workerRepositoryProvider = Provider<WorkerRepository>((ref) {
  return WorkerRepository(ref.watch(databaseProvider), ref.watch(uuidProvider));
});

final siteRepositoryProvider = Provider<SiteRepository>((ref) {
  return SiteRepository(ref.watch(databaseProvider), ref.watch(uuidProvider));
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
  );
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
  );
});

final advanceDebtRepositoryProvider = Provider<AdvanceDebtRepository>((ref) {
  return AdvanceDebtRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
  );
});

final payrollRepositoryProvider = Provider<PayrollRepository>((ref) {
  return PayrollRepository(
    database: ref.watch(databaseProvider),
    attendanceRepository: ref.watch(attendanceRepositoryProvider),
    advanceDebtRepository: ref.watch(advanceDebtRepositoryProvider),
    uuid: ref.watch(uuidProvider),
  );
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.watch(databaseProvider), ref.watch(uuidProvider));
});

final lastPaymentEndProvider = FutureProvider.family<DateTime?, String>((ref, workerId) {
  return ref.read(paymentRepositoryProvider).lastPaymentEnd(workerId);
});

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return SyncQueueRepository(ref.watch(databaseProvider));
});

final remoteDataSourceProvider = Provider<RemoteDataSource>((ref) {
  return FirebaseRemoteDataSource();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    queueRepository: ref.watch(syncQueueRepositoryProvider),
    remoteDataSource: ref.watch(remoteDataSourceProvider),
    connectivity: ref.watch(connectivityProvider),
  );
});
