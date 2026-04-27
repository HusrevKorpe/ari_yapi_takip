import 'dart:convert';
import 'dart:developer' as dev;
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
  // Exponential backoff: bir önceki fail sonrası tekrar denemeye uygun olduğu
  // en erken zaman. null → hemen denenebilir.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (m, from, to) async {
        // Her migration adımını kendi try/catch'iyle sarıyoruz ki beklenmeyen
        // bir hata olursa hangi adımın (ve hangi from→to geçişinin) patladığı
        // açıkça log'a düşsün ve hata warmUp() üzerinden UI'a taşınsın.
        await _runStep('v2: sites.daily_bonus', from < 2, () async {
          await _safeAddColumn(m, sites, sites.dailyBonus);
        });
        await _runStep('v3: payroll_payments table', from < 3, () async {
          try {
            await m.createTable(payrollPayments);
          } catch (e) {
            if (!e.toString().contains('already exists')) rethrow;
          }
        });
        await _runStep('v4: workers.pay_frequency', from < 4, () async {
          await _safeAddColumn(m, workers, workers.payFrequency);
        });
        await _runStep('v6: sync meta columns', from < 6, () async {
          await _ensureSyncMetaColumns(m);
        });
        await _runStep('v7: incomes table', from < 7, () async {
          try {
            await m.createTable(incomes);
          } catch (e) {
            if (!e.toString().contains('already exists')) rethrow;
          }
        });
        await _runStep('v8: sync_queue_items backoff columns', from < 8,
            () async {
          await _safeAddColumn(m, syncQueueItems, syncQueueItems.nextAttemptAt);
          await _safeAddColumn(m, syncQueueItems, syncQueueItems.lastError);
        });
        await _runStep('v9: payroll_payments unique period index', from < 9,
            () async {
          // Aynı (workerId, periodStart, periodEnd) için aktif (silinmemiş)
          // birden fazla kayıt varsa, en yenisi dışındakileri soft-delete et —
          // aksi halde partial unique index oluşturulamaz.
          await customStatement('''
            UPDATE payroll_payments
            SET deleted_at = COALESCE(deleted_at, $_epochZeroExpr),
                sync_version = sync_version + 1
            WHERE id IN (
              SELECT p.id FROM payroll_payments p
              WHERE p.deleted_at IS NULL
                AND EXISTS (
                  SELECT 1 FROM payroll_payments q
                  WHERE q.deleted_at IS NULL
                    AND q.worker_id = p.worker_id
                    AND q.period_start = p.period_start
                    AND q.period_end = p.period_end
                    AND (q.paid_at > p.paid_at
                         OR (q.paid_at = p.paid_at AND q.id > p.id))
                )
            );
          ''');
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS '
            'payroll_payments_unique_active_period '
            'ON payroll_payments(worker_id, period_start, period_end) '
            'WHERE deleted_at IS NULL;',
          );
        });
      },
    );
  }

  /// SQLite'da `strftime('%s', 'now')` kadar dinamik default'ları ALTER
  /// içinde kullanamadığımız için epoch=0 sabiti yeterli — sadece duplicate
  /// kayıtları soft-delete olarak işaretliyoruz, gerçek tarih kritik değil.
  static const String _epochZeroExpr = '0';

  Future<void> _runStep(
    String label,
    bool shouldRun,
    Future<void> Function() body,
  ) async {
    if (!shouldRun) return;
    try {
      await body();
    } catch (e, st) {
      dev.log(
        'Migration adımı başarısız: $label — $e',
        name: 'AppDatabase',
        error: e,
        stackTrace: st,
      );
      throw Exception('Migration başarısız ($label): $e');
    }
  }

  /// Migration Drift'te lazy çalışır (ilk sorguda tetiklenir). Provider
  /// oluşurken hata yakalanamadığı için uygulama açılırken bu metod çağrılır;
  /// hata UI'a taşınıp kullanıcıya gösterilir.
  Future<void> warmUp() async {
    await customSelect('SELECT 1').get();
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
    // Boş orgId ile gelirse kuyruğa yazmıyoruz (syncService nasılsa reddeder),
    // ama sessizce düşürmek "veriler Firestore'a gitmiyor" şikayetinin en sık
    // sebebi oldu. Gözle görünür log + audit bırak ki teşhis mümkün olsun.
    if (organizationId.isEmpty) {
      dev.log(
        'upsertQueueItem organizationId boş — atlandı '
        '($entityType/$entityId action=$action). Auth/bootstrap tamamlanmadan '
        'yazma denendi.',
        name: 'AppDatabase',
      );
      await addAudit(
        id: id,
        entityType: entityType,
        entityId: entityId,
        message: 'Sync atlandı: organizationId boş ($action)',
      );
      return;
    }

    if (action == 'delete') {
      // Offline create + delete: entity Firestore'a hiç gönderilmeden silinirse
      // ghost document oluşmaması için pending upsert'i iptal et, delete'i de
      // ekleme.
      final cancelledUpserts = await (delete(syncQueueItems)
            ..where(
              (q) =>
                  q.entityType.equals(entityType) &
                  q.entityId.equals(entityId) &
                  q.action.equals('upsert') &
                  q.status.equals('pending'),
            ))
          .go();
      if (cancelledUpserts > 0) return; // upsert iptal edildi, delete'e gerek yok

      // Aynı entity için eski pending delete'leri de temizle — bootstrap
      // re-run'larında aynı silmenin tekrar tekrar kuyruğa eklenmesini önler.
      await (delete(syncQueueItems)
            ..where(
              (q) =>
                  q.entityType.equals(entityType) &
                  q.entityId.equals(entityId) &
                  q.action.equals('delete') &
                  q.status.equals('pending'),
            ))
          .go();
    } else {
      // Aynı entity için eski pending upsert'leri sil — aksi halde backoff'da
      // bekleyen bayat payload, yeni kaydın üzerine Firestore'a yazılıp en
      // son değişiklikleri ezer (data loss on rapid re-saves).
      await (delete(syncQueueItems)
            ..where(
              (q) =>
                  q.entityType.equals(entityType) &
                  q.entityId.equals(entityId) &
                  q.action.equals(action) &
                  q.status.equals('pending'),
            ))
          .go();
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

  /// Pull tarafında tespit edilen çakışmaları (uzak yerelin üzerine yazıldı,
  /// uzaktaki değişiklik bekleyen yerel kayıt nedeniyle atlandı, vs.) kalıcı
  /// olarak audit_logs içine yazar. Ayrı tablo açmak yerine type prefix'i ile
  /// işaretliyoruz; UI bu kayıtları stream üzerinden listeleyip kullanıcıya
  /// gösteriyor.
  Future<void> addSyncConflict({
    required String id,
    required String kind, // 'overwritten' | 'pending_skipped' | 'remote_stale'
    required String entityType,
    required String entityId,
    required String message,
  }) {
    return into(auditLogs).insert(
      AuditLogsCompanion.insert(
        id: id,
        entityType: 'sync_conflict_${kind}_$entityType',
        entityId: entityId,
        message: message,
      ),
    );
  }

  Stream<int> unseenConflictCount(DateTime since) {
    final countExp = auditLogs.id.count();
    final query = selectOnly(auditLogs)
      ..addColumns([countExp])
      ..where(
        auditLogs.entityType.like('sync_conflict_%') &
            auditLogs.createdAt.isBiggerThanValue(since),
      );
    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  Future<List<AuditLog>> recentConflicts({int limit = 50}) {
    final query = select(auditLogs)
      ..where((a) => a.entityType.like('sync_conflict_%'))
      ..orderBy([(a) => OrderingTerm.desc(a.createdAt)])
      ..limit(limit);
    return query.get();
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
