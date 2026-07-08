import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ari_yapi_takip/app/app.dart';
import 'package:ari_yapi_takip/core/providers.dart';
import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertFailedItem(String id) {
    return db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: id,
            entityType: 'worker',
            entityId: 'w-$id',
            action: 'upsert',
            status: const Value('failed_permanent'),
            lastError: const Value('permission-denied'),
          ),
        );
  }

  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(body: SyncFailureBanner(count: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('banner dokununca kayıt listesi dialog\'u açılır', (tester) async {
    await insertFailedItem('1');
    await pumpBanner(tester);

    // Banner görünür.
    expect(find.textContaining('senkronize edilemedi'), findsOneWidget);

    // Dokun → dialog açılmalı (eskiden fire-and-forget async'te hata yutulabiliyordu).
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.text('Senkronize edilemeyen kayıtlar'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsWidgets);
    expect(find.text('Kalıcı Olarak Sil'), findsOneWidget);
    expect(find.text('Tümünü Tekrar Dene'), findsOneWidget);
  });

  testWidgets('Kalıcı Olarak Sil → onay → kayıtlar silinir', (tester) async {
    await insertFailedItem('1');
    await insertFailedItem('2');
    await pumpBanner(tester);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    // Silme akışını başlat.
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pumpAndSettle();

    // Onay dialog'u.
    expect(find.text('Kayıtları kalıcı olarak sil?'), findsOneWidget);
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();

    // Kuyrukta failed_permanent kayıt kalmamalı.
    final repo = SyncQueueRepository(db);
    final remaining = await repo.failedPermanentItems();
    expect(remaining, isEmpty);
  });

  testWidgets('Vazgeç → kayıtlar korunur', (tester) async {
    await insertFailedItem('1');
    await pumpBanner(tester);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    final repo = SyncQueueRepository(db);
    final remaining = await repo.failedPermanentItems();
    expect(remaining, hasLength(1));
  });
}
