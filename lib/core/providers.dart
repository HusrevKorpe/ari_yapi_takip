import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/auth/auth_repository.dart';
import '../data/auth/auth_state.dart';
import '../data/auth/organization_service.dart';
import '../data/local/app_database.dart';
import '../data/local/local_preferences.dart';
import '../data/local/repositories.dart';
import '../data/remote/firebase_remote_data_source.dart';
import '../data/sync/sync_context.dart';
import '../data/sync/bootstrap_service.dart';
import '../data/sync/pull_sync_service.dart';
import '../data/sync/sync_service.dart';

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Preferences & SyncContext
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

final workerRepositoryProvider = Provider<WorkerRepository>((ref) {
  return WorkerRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final siteRepositoryProvider = Provider<SiteRepository>((ref) {
  return SiteRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final incomeRepositoryProvider = Provider<IncomeRepository>((ref) {
  return IncomeRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final advanceDebtRepositoryProvider = Provider<AdvanceDebtRepository>((ref) {
  return AdvanceDebtRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final payrollRepositoryProvider = Provider<PayrollRepository>((ref) {
  return PayrollRepository(
    database: ref.watch(databaseProvider),
    attendanceRepository: ref.watch(attendanceRepositoryProvider),
    advanceDebtRepository: ref.watch(advanceDebtRepositoryProvider),
    uuid: ref.watch(uuidProvider),
    syncContext: ref.watch(syncContextProvider),
  );
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(
    ref.watch(databaseProvider),
    ref.watch(uuidProvider),
    ref.watch(syncContextProvider),
  );
});

final siteReportRepositoryProvider = Provider<SiteReportRepository>((ref) {
  return SiteReportRepository(ref.watch(databaseProvider));
});

final siteReportProvider =
    FutureProvider.family<SiteReportData, String>((ref, siteId) {
  return ref.watch(siteReportRepositoryProvider).getReport(siteId);
});

// ---------------------------------------------------------------------------
// Data stream providers
// ---------------------------------------------------------------------------

final lastPaymentEndProvider = FutureProvider.family<DateTime?, String>((
  ref,
  workerId,
) {
  return ref.read(paymentRepositoryProvider).lastPaymentEnd(workerId);
});

final workerPaymentsProvider =
    StreamProvider.family<List<PayrollPayment>, String>((ref, workerId) {
      return ref.watch(paymentRepositoryProvider).watchWorkerPayments(workerId);
    });

final workerAdvanceDebtsProvider =
    StreamProvider.family<List<AdvanceDebt>, String>((ref, workerId) {
      return ref.watch(advanceDebtRepositoryProvider).watchByWorker(workerId);
    });

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

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
