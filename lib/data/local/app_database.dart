import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// Sync meta columns mixin – reused by all entity tables
// ---------------------------------------------------------------------------
mixin SyncMeta on Table {
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get lastModifiedBy => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get syncVersion => integer().withDefault(const Constant(0))();
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class AdminManagers extends Table {
  TextColumn get id => text()();
  TextColumn get phone => text()();
  TextColumn get displayName => text()();
  TextColumn get organizationId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Workers extends Table with SyncMeta {
  TextColumn get id => text()();
  TextColumn get fullName => text()();
  RealColumn get dailyWage => real()();
  TextColumn get defaultSiteId => text().nullable()();
  TextColumn get payFrequency => text().withDefault(const Constant('weekly'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sites extends Table with SyncMeta {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get code => text()();
  RealColumn get dailyBonus => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AttendanceEntries extends Table with SyncMeta {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  DateTimeColumn get workDate => dateTime()();
  TextColumn get status => text()();
  TextColumn get siteId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workerId, workDate},
  ];
}

class Expenses extends Table with SyncMeta {
  TextColumn get id => text()();
  DateTimeColumn get expenseDate => dateTime()();
  RealColumn get amount => real()();
  TextColumn get category => text()();
  TextColumn get siteId => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Incomes extends Table with SyncMeta {
  TextColumn get id => text()();
  DateTimeColumn get incomeDate => dateTime()();
  RealColumn get amount => real()();
  TextColumn get category => text()();
  TextColumn get siteId => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AdvanceDebts extends Table with SyncMeta {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  DateTimeColumn get eventDate => dateTime()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  TextColumn get settledMonth => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PayrollPayments extends Table with SyncMeta {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PayrollSnapshots extends Table with SyncMeta {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  TextColumn get month => text()();
  RealColumn get workedDayEquivalent => real()();
  RealColumn get gross => real()();
  RealColumn get deductions => real()();
  RealColumn get net => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workerId, month},
  ];
}

class SyncQueueItems extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  TextColumn get organizationId => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get processedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get message => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [
    AdminManagers,
    Workers,
    Sites,
    AttendanceEntries,
    Expenses,
    Incomes,
    AdvanceDebts,
    PayrollPayments,
    PayrollSnapshots,
    SyncQueueItems,
    AuditLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await _safeAddColumn(m, sites, sites.dailyBonus);
        }
        if (from < 3) {
          try {
            await m.createTable(payrollPayments);
          } catch (_) {}
        }
        if (from < 4) {
          await _safeAddColumn(m, workers, workers.payFrequency);
        }
        // v5+v6: Sync meta columns. Uses _safeAddColumn so it's safe to
        // re-run even if a previous partial migration already added some.
        if (from < 6) {
          await _ensureSyncMetaColumns(m);
        }
        if (from < 7) {
          await m.createTable(incomes);
        }
      },
    );
  }

  /// Adds all sync meta columns to all entity tables.
  /// Safe to call multiple times - skips columns that already exist.
  /// Uses raw SQL for datetime columns because SQLite ALTER TABLE
  /// does not allow non-constant defaults like CURRENT_TIMESTAMP.
  Future<void> _ensureSyncMetaColumns(Migrator m) async {
    const epoch = 0; // constant default for datetime columns

    // Workers: 4 sync columns (updatedAt already exists)
    await _safeAddColumn(m, workers, workers.deletedAt);
    await _safeAddColumn(m, workers, workers.lastModifiedBy);
    await _safeAddColumn(m, workers, workers.deviceId);
    await _safeAddColumn(m, workers, workers.syncVersion);

    // Sites: updatedAt + 4 sync columns
    await _safeRawAddColumn(
      'sites',
      'updated_at',
      'INTEGER NOT NULL DEFAULT $epoch',
    );
    await _safeAddColumn(m, sites, sites.deletedAt);
    await _safeAddColumn(m, sites, sites.lastModifiedBy);
    await _safeAddColumn(m, sites, sites.deviceId);
    await _safeAddColumn(m, sites, sites.syncVersion);

    // AttendanceEntries: createdAt + 4 sync columns
    await _safeRawAddColumn(
      'attendance_entries',
      'created_at',
      'INTEGER NOT NULL DEFAULT $epoch',
    );
    await _safeAddColumn(m, attendanceEntries, attendanceEntries.deletedAt);
    await _safeAddColumn(
      m,
      attendanceEntries,
      attendanceEntries.lastModifiedBy,
    );
    await _safeAddColumn(m, attendanceEntries, attendanceEntries.deviceId);
    await _safeAddColumn(m, attendanceEntries, attendanceEntries.syncVersion);

    // Expenses: updatedAt + 4 sync columns
    await _safeRawAddColumn(
      'expenses',
      'updated_at',
      'INTEGER NOT NULL DEFAULT $epoch',
    );
    await _safeAddColumn(m, expenses, expenses.deletedAt);
    await _safeAddColumn(m, expenses, expenses.lastModifiedBy);
    await _safeAddColumn(m, expenses, expenses.deviceId);
    await _safeAddColumn(m, expenses, expenses.syncVersion);

    // AdvanceDebts: updatedAt + 4 sync columns
    await _safeRawAddColumn(
      'advance_debts',
      'updated_at',
      'INTEGER NOT NULL DEFAULT $epoch',
    );
    await _safeAddColumn(m, advanceDebts, advanceDebts.deletedAt);
    await _safeAddColumn(m, advanceDebts, advanceDebts.lastModifiedBy);
    await _safeAddColumn(m, advanceDebts, advanceDebts.deviceId);
    await _safeAddColumn(m, advanceDebts, advanceDebts.syncVersion);

    // PayrollPayments: updatedAt + 4 sync columns
    await _safeRawAddColumn(
      'payroll_payments',
      'updated_at',
      'INTEGER NOT NULL DEFAULT $epoch',
    );
    await _safeAddColumn(m, payrollPayments, payrollPayments.deletedAt);
    await _safeAddColumn(m, payrollPayments, payrollPayments.lastModifiedBy);
    await _safeAddColumn(m, payrollPayments, payrollPayments.deviceId);
    await _safeAddColumn(m, payrollPayments, payrollPayments.syncVersion);

    // PayrollSnapshots: updatedAt + 4 sync columns
    await _safeRawAddColumn(
      'payroll_snapshots',
      'updated_at',
      'INTEGER NOT NULL DEFAULT $epoch',
    );
    await _safeAddColumn(m, payrollSnapshots, payrollSnapshots.deletedAt);
    await _safeAddColumn(m, payrollSnapshots, payrollSnapshots.lastModifiedBy);
    await _safeAddColumn(m, payrollSnapshots, payrollSnapshots.deviceId);
    await _safeAddColumn(m, payrollSnapshots, payrollSnapshots.syncVersion);

    // SyncQueueItems: organizationId
    await _safeAddColumn(m, syncQueueItems, syncQueueItems.organizationId);
  }

  /// Adds a column using raw SQL with a constant default.
  /// Used for datetime columns where Drift's currentDateAndTime
  /// generates a non-constant expression that SQLite rejects in ALTER TABLE.
  Future<void> _safeRawAddColumn(
    String table,
    String column,
    String definition,
  ) async {
    try {
      await customStatement(
        'ALTER TABLE "$table" ADD COLUMN "$column" $definition;',
      );
    } catch (e) {
      if (e.toString().contains('duplicate column')) return;
      rethrow;
    }
  }

  /// Adds a column via Drift, ignoring "duplicate column" errors.
  static Future<void> _safeAddColumn(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    try {
      await m.addColumn(table, column);
    } catch (e) {
      if (e.toString().contains('duplicate column')) return;
      if (e.toString().contains('non-constant default')) return;
      rethrow;
    }
  }

  Future<void> upsertQueueItem({
    required String id,
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
    String organizationId = '',
  }) async {
    // Boş orgId ile kuyruğa item eklenmez — asla senkronize edilemezler.
    if (organizationId.isEmpty) return;

    // Offline create + delete senaryosu: entity Firestore'a hiç gönderilmeden
    // silinirse ghost document oluşmaması için pending upsert'i iptal et,
    // delete'i de ekleme.
    if (action == 'delete') {
      final cancelled = await (delete(syncQueueItems)
            ..where(
              (q) =>
                  q.entityId.equals(entityId) &
                  q.action.equals('upsert') &
                  q.status.equals('pending'),
            ))
          .go();
      if (cancelled > 0) return; // upsert iptal edildi, delete'e gerek yok
    }

    await into(syncQueueItems).insertOnConflictUpdate(
      SyncQueueItemsCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: Value(jsonEncode(payload)),
        organizationId: Value(organizationId),
      ),
    );
  }

  /// Boş organizationId ile birikmiş eski orphan kuyruk öğelerini temizler.
  Future<void> deleteOrphanQueueItems() {
    return (delete(syncQueueItems)
          ..where((q) => q.organizationId.equals('')))
        .go();
  }

  Future<void> addAudit({
    required String id,
    required String entityType,
    required String entityId,
    required String message,
  }) {
    return into(auditLogs).insert(
      AuditLogsCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        message: message,
      ),
    );
  }

  Future<void> clearTenantScopedData() async {
    await transaction(() async {
      await delete(syncQueueItems).go();
      await delete(auditLogs).go();
      await delete(payrollSnapshots).go();
      await delete(payrollPayments).go();
      await delete(advanceDebts).go();
      await delete(incomes).go();
      await delete(expenses).go();
      await delete(attendanceEntries).go();
      await delete(sites).go();
      await delete(workers).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ari_yapi_takip.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
