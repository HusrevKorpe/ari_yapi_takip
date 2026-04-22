import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class SiteRepository {
  SiteRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Site>> watchActiveSites() {
    final query = _db.select(_db.sites)
      ..where((s) => s.isActive.equals(true) & s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm(expression: s.name)]);
    return query.watch();
  }

  Future<void> createSite({
    required String name,
    required String code,
    double dailyBonus = 0,
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.sites).insert(
        SitesCompanion.insert(
          id: id,
          name: name,
          code: code,
          dailyBonus: Value(dailyBonus),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> updateSiteBonus({
    required String siteId,
    required double dailyBonus,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
        SitesCompanion(
          dailyBonus: Value(dailyBonus),
          updatedAt: Value(DateTime.now()),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: siteId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deactivateSite({required String siteId}) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
        SitesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: siteId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }
}
