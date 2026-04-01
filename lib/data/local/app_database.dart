import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

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

class Workers extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();
  RealColumn get dailyWage => real()();
  TextColumn get defaultSiteId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sites extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get code => text()();
  RealColumn get dailyBonus => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AttendanceEntries extends Table {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  DateTimeColumn get workDate => dateTime()();
  TextColumn get status => text()();
  TextColumn get siteId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workerId, workDate},
  ];
}

class Expenses extends Table {
  TextColumn get id => text()();
  DateTimeColumn get expenseDate => dateTime()();
  RealColumn get amount => real()();
  TextColumn get category => text()();
  TextColumn get siteId => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AdvanceDebts extends Table {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  DateTimeColumn get eventDate => dateTime()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  TextColumn get settledMonth => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PayrollPayments extends Table {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PayrollSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get workerId => text()();
  TextColumn get month => text()();
  RealColumn get workedDayEquivalent => real()();
  RealColumn get gross => real()();
  RealColumn get deductions => real()();
  RealColumn get net => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

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

@DriftDatabase(
  tables: [
    AdminManagers,
    Workers,
    Sites,
    AttendanceEntries,
    Expenses,
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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(sites, sites.dailyBonus);
        }
        if (from < 3) {
          await m.createTable(payrollPayments);
        }
      },
    );
  }

  Future<void> upsertQueueItem({
    required String id,
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) {
    return into(syncQueueItems).insertOnConflictUpdate(
      SyncQueueItemsCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: Value(jsonEncode(payload)),
      ),
    );
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
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ari_yapi_takip.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
