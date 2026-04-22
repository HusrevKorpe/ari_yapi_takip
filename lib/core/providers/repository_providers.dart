import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/repositories.dart';
import 'database_providers.dart';
import 'preferences_providers.dart';

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
