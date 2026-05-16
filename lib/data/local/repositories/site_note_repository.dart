import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class SiteNoteRepository {
  SiteNoteRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<SiteNote>> watchNotesForSite(String siteId) {
    final query = _db.select(_db.siteNotes)
      ..where((n) => n.siteId.equals(siteId) & n.deletedAt.isNull())
      ..orderBy([
        (n) => OrderingTerm(
          expression: n.noteDate,
          mode: OrderingMode.desc,
        ),
        (n) => OrderingTerm(
          expression: n.createdAt,
          mode: OrderingMode.desc,
        ),
      ]);
    return query.watch();
  }

  Future<void> saveNote({
    String? id,
    required String siteId,
    required DateTime noteDate,
    required String content,
  }) async {
    final noteId = id ?? _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      int nextVersion = 1;
      if (id != null) {
        final existing = await (_db.select(_db.siteNotes)
              ..where((n) => n.id.equals(id)))
            .getSingleOrNull();
        if (existing != null) nextVersion = existing.syncVersion + 1;
      }

      await _db.into(_db.siteNotes).insertOnConflictUpdate(
        SiteNotesCompanion.insert(
          id: noteId,
          siteId: siteId,
          noteDate: noteDate,
          content: content,
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.siteNotes)
            ..where((n) => n.id.equals(noteId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site_note',
        entityId: noteId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deleteNote({required String noteId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.siteNotes)
            ..where((n) => n.id.equals(noteId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.siteNotes)..where((n) => n.id.equals(noteId)))
          .write(
        SiteNotesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.siteNotes)
            ..where((n) => n.id.equals(noteId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site_note',
        entityId: noteId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }
}
