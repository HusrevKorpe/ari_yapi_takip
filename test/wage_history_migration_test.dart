import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';

/// v14→v15 migration testi: workers.wage_history sütunu güvenle eklenmeli ve
/// mevcut çalışan satırları bozulmadan, wageHistory = null ile taşınmalı
/// (yani zam geçmişi olmayan mevcut kayıtların davranışı DEĞİŞMEZ).
void main() {
  test('v14→v15: wage_history sütunu eklenir, mevcut kayıt korunur', () async {
    final dir = await Directory.systemTemp.createTemp('wage_migr');
    final file = File('${dir.path}/app.db');

    // 1) Güncel şemada (v15) bir DB kur ve bir çalışan ekle.
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await db.into(db.workers).insert(
          WorkersCompanion.insert(
            id: 'w1',
            fullName: 'Eski Kayıt',
            dailyWage: 2000,
          ),
        );
    await db.close();

    // 2) "v14 kurulumu" taklidi: wage_history sütununu düş ve şema sürümünü
    // 14'e çek. Böylece yeniden açılışta gerçek migration yolu çalışır.
    final raw = NativeDatabase(file);
    var probe = AppDatabase.forTesting(raw);
    await probe.customStatement('ALTER TABLE workers DROP COLUMN wage_history');
    await probe.customStatement('PRAGMA user_version = 14');
    await probe.close();

    // 3) Yeniden aç → onUpgrade(14→15) tetiklenir, sütun geri eklenir.
    db = AppDatabase.forTesting(NativeDatabase(file));
    final worker =
        await (db.select(db.workers)..where((w) => w.id.equals('w1')))
            .getSingle();

    expect(worker.fullName, 'Eski Kayıt', reason: 'kayıt korunmalı');
    expect(worker.dailyWage, 2000);
    expect(
      worker.wageHistory,
      isNull,
      reason: 'mevcut kayıtta zam geçmişi yok → davranış değişmez',
    );

    // Sütun gerçekten yazılabilir mi?
    await (db.update(db.workers)..where((w) => w.id.equals('w1'))).write(
      const WorkersCompanion(wageHistory: Value('[]')),
    );
    final updated =
        await (db.select(db.workers)..where((w) => w.id.equals('w1')))
            .getSingle();
    expect(updated.wageHistory, '[]');

    await db.close();
    await dir.delete(recursive: true);
  });
}
