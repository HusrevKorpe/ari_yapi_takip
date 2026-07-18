import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../local/app_database.dart';
import 'sync_collections.dart';

class PullSyncService {
  PullSyncService({
    required AppDatabase database,
    required String deviceId,
    void Function(Object error)? onPermissionDenied,
  })  : _db = database,
        _deviceId = deviceId,
        _onPermissionDenied = onPermissionDenied;

  final AppDatabase _db;
  final String _deviceId;

  /// Kalıcı `permission-denied` (yetki/kural/üyelik sorunu) tespit edildiğinde
  /// tam olarak bir kez çağrılır. AuthGate bunu yakalayıp sessiz 5 sn'lik retry
  /// döngüsü yerine kullanıcıya hata ekranı gösterir. Geçici ağ hataları
  /// (`unavailable` vb.) bu callback'i TETİKLEMEZ — yalnızca kalıcı yetki reddi.
  final void Function(Object error)? _onPermissionDenied;

  /// Kalıcı yetki reddi üst katmana yalnızca bir kez bildirilsin diye bayrak.
  /// `dispose()` (dolayısıyla `start()` → "Tekrar Dene") ile sıfırlanır.
  bool _fatalReported = false;

  final Map<String, StreamSubscription<dynamic>> _subs = {};

  /// Koleksiyon başına üst üste gelen dinleyici hatası sayısı. Başarılı bir
  /// snapshot gelince sıfırlanır; yalnızca eşiği aşınca görünür uyarı basılır.
  final Map<String, int> _failureCounts = {};

  String? _activeOrganizationId;

  /// Bu sayıya ulaşana kadarki ardışık hatalar geçici kabul edilip (yeni açılan
  /// listen akışına auth token'ın henüz iliştirilmemesi gibi, reconnect ile
  /// kendini iyileştiren durumlar) sessizce loglanır. Bu sayıda görünür uyarı
  /// basılır; kalıcı yetki/kural sorununu ayırt etmeyi sağlar.
  static const _maxTransientFailures = 3;

  /// `permission-denied` bu kadar üst üste tekrarlarsa artık yeni açılan akışa
  /// token iliştirme gecikmesi değil, kalıcı yetki/kural/üyelik sorunudur;
  /// senkronizasyon durdurulup `_onPermissionDenied` ile UI'a bildirilir.
  /// Cold-start'taki geçici token gecikmelerine karşı `_maxTransientFailures`'ın
  /// üstünde tutulur (~25 sn'lik kendini-iyileştirme payı).
  static const _fatalPermissionFailures = 5;

  bool get _isFirebaseAvailable => Firebase.apps.isNotEmpty;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const _collectionMap = kEntityCollections;

  Future<void> start(String organizationId) async {
    if (!_isFirebaseAvailable || organizationId.isEmpty) return;
    if (_activeOrganizationId == organizationId && _subs.isNotEmpty) return;

    await dispose();
    _activeOrganizationId = organizationId;

    for (final entry in _collectionMap.entries) {
      _subscribe(organizationId, entry.key, entry.value);
    }
  }

  void _subscribe(String organizationId, String entityType, String collection) {
    _subs[entityType]?.cancel();
    final sub = _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection(collection)
        .snapshots()
        .asyncMap((snapshot) async {
          for (final change in snapshot.docChanges) {
            final payload = change.doc.data();
            if (payload == null) continue;
            try {
              await _apply(entityType, payload);
            } catch (e, st) {
              dev.log(
                'PullSync [$entityType] uygulama hatası: $e',
                name: 'PullSyncService',
                error: e,
                stackTrace: st,
              );
            }
          }
        })
        .listen(
          (_) => resetFailures(entityType),
          onError: (Object error) {
            // Sayım/kalıcı-reddi kararı tek (test edilebilir) noktada verilir;
            // yalnızca "yeniden bağlan" dönerse 5 sn sonra reconnect edilir.
            if (handleListenerError(entityType, error)) {
              Future.delayed(const Duration(seconds: 5), () {
                if (_activeOrganizationId == organizationId) {
                  _subscribe(organizationId, entityType, collection);
                }
              });
            }
          },
        );
    _subs[entityType] = sub;
  }

  /// Başarılı bir snapshot geldiğinde koleksiyonun geçici hata sayacını sıfırlar.
  @visibleForTesting
  void resetFailures(String entityType) {
    _failureCounts[entityType] = 0;
  }

  /// Bir dinleyici hatasını işler: sayacı artırır, kalıcı `permission-denied`
  /// ise fatal olarak (bir kez) raporlayıp döngüyü keser. Çağıranın yeniden
  /// bağlanması gerekiyorsa `true`, döngü kesildiyse `false` döner.
  @visibleForTesting
  bool handleListenerError(String entityType, Object error) {
    final failures = (_failureCounts[entityType] ?? 0) + 1;
    _failureCounts[entityType] = failures;

    // Kalıcı yetki reddi: yeni açılan listen akışına token iliştirme gecikmesi
    // ilk birkaç reconnect'te iyileşir; bu eşiği de aşan `permission-denied`
    // gerçek bir kural/üyelik sorunudur. Kurallar tüm koleksiyonlar için aynı
    // olduğundan biri kalıcı reddediliyorsa hepsi reddedilir — dinleyicileri
    // durdur ve sessiz döngü yerine üst katmana (AuthGate) bir kez bildir.
    if (_isPermissionDenied(error) && failures >= _fatalPermissionFailures) {
      dev.log(
        'PullSync [$entityType] kalıcı permission-denied ($failures. deneme) '
        '— senkronizasyon durduruldu, kullanıcıya bildiriliyor: $error',
        name: 'PullSyncService',
        level: 1000, // SEVERE
        error: error,
      );
      _reportFatalPermissionDenied(error);
      return false; // Yeniden bağlanma; döngüyü kes.
    }

    // İlk birkaç permission-denied çoğunlukla yeni açılan listen akışına auth
    // token'ının henüz iliştirilmemesinden kaynaklanır ve reconnect ile iyileşir
    // — bunları düşük seviyede sessizce logla. Yalnızca üst üste eşiği aşınca
    // (kalıcı yetki/kural sorunu ihtimali) tam olarak bir kez görünür uyarı bas;
    // sonrasında her 5 sn'de tekrar etmemek için tekrar sessizleş.
    if (failures < _maxTransientFailures) {
      dev.log(
        'PullSync [$entityType] geçici hata (#$failures), '
        'yeniden baglaniyor: $error',
        name: 'PullSyncService',
        level: 500, // FINE
      );
    } else if (failures == _maxTransientFailures) {
      dev.log(
        'PullSync [$entityType] üst üste $failures kez başarısız — '
        'kalıcı yetki/kural sorunu olabilir, yeniden baglaniyor: $error',
        name: 'PullSyncService',
        level: 900, // WARNING
        error: error,
      );
    }
    return true;
  }

  Future<void> dispose() async {
    final cancellations = _subs.values.map((sub) => sub.cancel()).toList();
    _subs.clear();
    _failureCounts.clear();
    _activeOrganizationId = null;
    _fatalReported = false;
    await Future.wait(cancellations);
  }

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  /// Kalıcı yetki reddini üst katmana bir kez bildirir ve tüm pull
  /// dinleyicilerini durdurur — kalıcı hatada 5 sn'lik yeniden bağlanma döngüsü
  /// anlamsızdır. `_activeOrganizationId` sıfırlandığından diğer koleksiyonların
  /// beklemede olan yeniden-bağlanma zamanlayıcıları da devre dışı kalır.
  /// `start()` (Tekrar Dene) yeniden çağrılınca `dispose()` bayrağı sıfırlar.
  void _reportFatalPermissionDenied(Object error) {
    if (_fatalReported) return;
    _fatalReported = true;
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
    _failureCounts.clear();
    _activeOrganizationId = null;
    _onPermissionDenied?.call(error);
  }

  Future<void> _apply(String entityType, Map<String, dynamic> data) async {
    switch (entityType) {
      case 'worker':
        await _upsertWorker(data);
        return;
      case 'site':
        await _upsertSite(data);
        return;
      case 'attendance':
        await _upsertAttendance(data);
        return;
      case 'expense':
        await _upsertExpense(data);
        return;
      case 'income':
        await _upsertIncome(data);
        return;
      case 'partner_payment':
        await _upsertPartnerPayment(data);
        return;
      case 'advance_debt':
        await _upsertAdvanceDebt(data);
        return;
      case 'payroll_payment':
        await _upsertPayrollPayment(data);
        return;
      case 'payroll_snapshot':
        await _upsertPayrollSnapshot(data);
        return;
      case 'site_note':
        await _upsertSiteNote(data);
        return;
      default:
        return;
    }
  }

  /// Kendi cihazımızdan gelen echo'yu atla; aynı versiyonu tekrar yazma.
  bool _isEcho(Map<String, dynamic> data, int remoteVersion, int localVersion) {
    final remoteDeviceId = data['cihazId']?.toString() ?? '';
    return remoteVersion <= localVersion && remoteDeviceId == _deviceId;
  }

  /// Local'de bu entity için henüz push edilmemiş değişiklik var mı?
  /// Varsa pull yazımını atla — aksi halde pending local edit remote
  /// tarafından overwrite edilir (concurrent edit data loss).
  Future<bool> _hasPendingPush(String entityType, String entityId) async {
    final q = _db.select(_db.syncQueueItems)
      ..where(
        (q) =>
            q.entityType.equals(entityType) &
            q.entityId.equals(entityId) &
            q.status.equals('pending'),
      )
      ..limit(1);
    final row = await q.getSingleOrNull();
    return row != null;
  }

  Future<void> _upsertWorker(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('worker', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.workers,
    )..where((w) => w.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.workers)
        .insertOnConflictUpdate(
          WorkersCompanion.insert(
            id: id,
            fullName: _str(_value(data, 'adSoyad', 'fullName')),
            dailyWage: _double(_value(data, 'gunlukUcret', 'dailyWage')),
            wageHistory: Value(
              _nullableStr(_value(data, 'ucretGecmisi', 'wageHistory')),
            ),
            defaultSiteId: Value(
              _nullableStr(
                _value(data, 'varsayilanSantiyeId', 'defaultSiteId'),
              ),
            ),
            payFrequency: Value(
              _str(
                _value(data, 'odemePeriyodu', 'payFrequency'),
                fallback: 'weekly',
              ),
            ),
            isActive: Value(
              _bool(_value(data, 'aktifMi', 'isActive'), fallback: true),
            ),
            receivesBonus: Value(
              _bool(
                _value(data, 'primAliyor', 'receivesBonus'),
                fallback: true,
              ),
            ),
            notes: Value(_nullableStr(_value(data, 'notlar', 'notes'))),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertSite(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('site', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.sites,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.sites)
        .insertOnConflictUpdate(
          SitesCompanion.insert(
            id: id,
            name: _str(_value(data, 'ad', 'name')),
            code: _str(_value(data, 'kod', 'code')),
            dailyBonus: Value(
              _double(_value(data, 'gunlukPrim', 'dailyBonus')),
            ),
            bonusHistory: Value(
              _nullableStr(_value(data, 'primGecmisi', 'bonusHistory')),
            ),
            isActive: Value(
              _bool(_value(data, 'aktifMi', 'isActive'), fallback: true),
            ),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertAttendance(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('attendance', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.attendanceEntries,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.attendanceEntries)
        .insertOnConflictUpdate(
          AttendanceEntriesCompanion.insert(
            id: id,
            workerId: _str(_value(data, 'calisanId', 'workerId')),
            workDate: _date(_value(data, 'tarih', 'workDate')),
            status: _str(_value(data, 'durum', 'status')),
            siteId: Value(_nullableStr(_value(data, 'santiyeId', 'siteId'))),
            secondSiteId: Value(
              _nullableStr(_value(data, 'ikinciSantiyeId', 'secondSiteId')),
            ),
            note: Value(_nullableStr(_value(data, 'not', 'note'))),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertExpense(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('expense', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.expenses,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.expenses)
        .insertOnConflictUpdate(
          ExpensesCompanion.insert(
            id: id,
            expenseDate: _date(_value(data, 'giderTarihi', 'expenseDate')),
            amount: _double(_value(data, 'tutar', 'amount')),
            category: _str(_value(data, 'kategori', 'category')),
            siteId: Value(_nullableStr(_value(data, 'santiyeId', 'siteId'))),
            description: Value(
              _nullableStr(_value(data, 'aciklama', 'description')),
            ),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertIncome(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('income', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.incomes,
    )..where((i) => i.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.incomes)
        .insertOnConflictUpdate(
          IncomesCompanion.insert(
            id: id,
            incomeDate: _date(_value(data, 'gelirTarihi', 'incomeDate')),
            amount: _double(_value(data, 'tutar', 'amount')),
            category: _str(_value(data, 'kategori', 'category')),
            siteId: Value(_nullableStr(_value(data, 'santiyeId', 'siteId'))),
            description: Value(
              _nullableStr(_value(data, 'aciklama', 'description')),
            ),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertPartnerPayment(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('partner_payment', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.partnerPayments,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.partnerPayments)
        .insertOnConflictUpdate(
          PartnerPaymentsCompanion.insert(
            id: id,
            paymentDate: _date(_value(data, 'odemeTarihi', 'paymentDate')),
            amount: _double(_value(data, 'tutar', 'amount')),
            partnerName: _str(_value(data, 'ortakAdi', 'partnerName')),
            description: Value(
              _nullableStr(_value(data, 'aciklama', 'description')),
            ),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertAdvanceDebt(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('advance_debt', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.advanceDebts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.advanceDebts)
        .insertOnConflictUpdate(
          AdvanceDebtsCompanion.insert(
            id: id,
            workerId: _str(_value(data, 'calisanId', 'workerId')),
            eventDate: _date(_value(data, 'islemTarihi', 'eventDate')),
            type: _str(_value(data, 'tur', 'type')),
            amount: _double(_value(data, 'tutar', 'amount')),
            note: Value(_nullableStr(_value(data, 'not', 'note'))),
            settledMonth: _str(_value(data, 'mahsupAy', 'settledMonth')),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertPayrollPayment(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('payroll_payment', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.payrollPayments,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.payrollPayments)
        .insertOnConflictUpdate(
          PayrollPaymentsCompanion.insert(
            id: id,
            workerId: _str(_value(data, 'calisanId', 'workerId')),
            periodStart: _date(_value(data, 'donemBaslangici', 'periodStart')),
            periodEnd: _date(_value(data, 'donemBitisi', 'periodEnd')),
            amount: _double(_value(data, 'tutar', 'amount')),
            paidAt: _date(_value(data, 'odemeTarihi', 'paidAt')),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertPayrollSnapshot(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('payroll_snapshot', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.payrollSnapshots,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    final rawDays = _value(data, 'gunlukDetay', 'attendanceDaysJson');
    final daysJson = rawDays is String && rawDays.isNotEmpty ? rawDays : null;

    await _db
        .into(_db.payrollSnapshots)
        .insertOnConflictUpdate(
          PayrollSnapshotsCompanion.insert(
            id: id,
            workerId: _str(_value(data, 'calisanId', 'workerId')),
            month: _str(_value(data, 'ay', 'month')),
            workedDayEquivalent: _double(
              _value(data, 'calisilanGunEsdegeri', 'workedDayEquivalent'),
            ),
            gross: _double(_value(data, 'brut', 'gross')),
            deductions: _double(_value(data, 'kesintiler', 'deductions')),
            net: _double(_value(data, 'net', 'net')),
            attendanceDaysJson: Value(daysJson),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  Future<void> _upsertSiteNote(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
    if (await _hasPendingPush('site_note', id)) {
      return;
    }
    final remoteVersion = _int(
      _value(data, 'senkronSurumu', 'syncVersion'),
      fallback: 1,
    );
    final existing = await (_db.select(
      _db.siteNotes,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      if (_isEcho(data, remoteVersion, existing.syncVersion)) return;
      if (remoteVersion < existing.syncVersion) return;
    }

    await _db
        .into(_db.siteNotes)
        .insertOnConflictUpdate(
          SiteNotesCompanion.insert(
            id: id,
            siteId: _str(_value(data, 'santiyeId', 'siteId')),
            noteDate: _date(_value(data, 'notTarihi', 'noteDate')),
            content: _str(_value(data, 'icerik', 'content')),
            createdAt: Value(
              _date(_value(data, 'olusturulmaTarihi', 'createdAt')),
            ),
            updatedAt: Value(
              _date(_value(data, 'guncellenmeTarihi', 'updatedAt')),
            ),
            deletedAt: Value(
              _nullableDate(_value(data, 'silinmeTarihi', 'deletedAt')),
            ),
            lastModifiedBy: Value(
              _str(_value(data, 'sonDegistiren', 'lastModifiedBy')),
            ),
            deviceId: Value(_str(_value(data, 'cihazId', 'deviceId'))),
            syncVersion: Value(remoteVersion),
          ),
        );
  }

  dynamic _value(Map<String, dynamic> data, String trKey, String enKey) {
    if (data.containsKey(trKey)) return data[trKey];
    return data[enKey];
  }

  String _str(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  String? _nullableStr(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  int _int(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _double(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }

  DateTime _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('Geçersiz tarih: $value');
    return parsed;
  }

  DateTime? _nullableDate(dynamic value) {
    if (value == null) return null;
    return _date(value);
  }
}
