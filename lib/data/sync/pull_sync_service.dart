import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_core/firebase_core.dart';

import '../local/app_database.dart';
import 'sync_collections.dart';

class PullSyncService {
  PullSyncService({required AppDatabase database, required String deviceId})
      : _db = database,
        _deviceId = deviceId;

  final AppDatabase _db;
  final String _deviceId;
  final Map<String, StreamSubscription<dynamic>> _subs = {};

  String? _activeOrganizationId;

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
          (_) {},
          onError: (Object error) {
            dev.log(
              'PullSync [$entityType] hata: $error — yeniden baglaniyor',
              name: 'PullSyncService',
            );
            Future.delayed(const Duration(seconds: 5), () {
              if (_activeOrganizationId == organizationId) {
                _subscribe(organizationId, entityType, collection);
              }
            });
          },
        );
    _subs[entityType] = sub;
  }

  Future<void> dispose() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    _activeOrganizationId = null;
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
      case 'advance_debt':
        await _upsertAdvanceDebt(data);
        return;
      case 'payroll_payment':
        await _upsertPayrollPayment(data);
        return;
      case 'payroll_snapshot':
        await _upsertPayrollSnapshot(data);
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

  Future<void> _upsertWorker(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
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

  Future<void> _upsertAdvanceDebt(Map<String, dynamic> data) async {
    final id = _str(data['id']);
    if (id.isEmpty) return;
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
