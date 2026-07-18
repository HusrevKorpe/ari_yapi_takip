import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';

/// v15→v16 migration testi: sites.bonus_history sütunu güvenle eklenmeli ve
/// mevcut şantiye satırları bozulmadan, bonusHistory = null ile taşınmalı
/// (yani prim geçmişi olmayan mevcut kayıtların davranışı DEĞİŞMEZ).
void main() {
  test('v15→v16: bonus_history sütunu eklenir, mevcut kayıt korunur', () async {
    final dir = await Directory.systemTemp.createTemp('bonus_migr');
    final file = File('${dir.path}/app.db');

    // 1) Güncel şemada (v16) bir DB kur ve bir şantiye ekle.
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 's1',
            name: 'Eski Şantiye',
            code: 'ESK',
            dailyBonus: const Value(200),
          ),
        );
    await db.close();

    // 2) "v15 kurulumu" taklidi: bonus_history sütununu düş ve şema sürümünü
    // 15'e çek. Böylece yeniden açılışta gerçek migration yolu çalışır.
    final raw = NativeDatabase(file);
    var probe = AppDatabase.forTesting(raw);
    await probe.customStatement('ALTER TABLE sites DROP COLUMN bonus_history');
    await probe.customStatement('PRAGMA user_version = 15');
    await probe.close();

    // 3) Yeniden aç → onUpgrade(15→16) tetiklenir, sütun geri eklenir.
    db = AppDatabase.forTesting(NativeDatabase(file));
    final site =
        await (db.select(db.sites)..where((s) => s.id.equals('s1'))).getSingle();

    expect(site.name, 'Eski Şantiye', reason: 'kayıt korunmalı');
    expect(site.dailyBonus, 200);
    expect(
      site.bonusHistory,
      isNull,
      reason: 'mevcut kayıtta prim geçmişi yok → davranış değişmez',
    );

    // Sütun gerçekten yazılabilir mi?
    await (db.update(db.sites)..where((s) => s.id.equals('s1'))).write(
      const SitesCompanion(bonusHistory: Value('[]')),
    );
    final updated =
        await (db.select(db.sites)..where((s) => s.id.equals('s1'))).getSingle();
    expect(updated.bonusHistory, '[]');

    await db.close();
    await dir.delete(recursive: true);
  });
}
