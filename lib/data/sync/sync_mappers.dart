import '../local/app_database.dart';

extension WorkerSyncExt on Worker {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'adSoyad': fullName,
    'gunlukUcret': dailyWage,
    'varsayilanSantiyeId': defaultSiteId,
    'odemePeriyodu': payFrequency,
    'aktifMi': isActive,
    'notlar': notes,
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}

extension SiteSyncExt on Site {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'ad': name,
    'kod': code,
    'gunlukPrim': dailyBonus,
    'aktifMi': isActive,
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}

extension AttendanceEntrySyncExt on AttendanceEntry {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'calisanId': workerId,
    'tarih': workDate.toIso8601String(),
    'durum': status,
    'santiyeId': siteId,
    'not': note,
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}

extension ExpenseSyncExt on Expense {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'giderTarihi': expenseDate.toIso8601String(),
    'tutar': amount,
    'kategori': category,
    'santiyeId': siteId,
    'aciklama': description,
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}

extension AdvanceDebtSyncExt on AdvanceDebt {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'calisanId': workerId,
    'islemTarihi': eventDate.toIso8601String(),
    'tur': type,
    'tutar': amount,
    'not': note,
    'mahsupAy': settledMonth,
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}

extension PayrollPaymentSyncExt on PayrollPayment {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'calisanId': workerId,
    'donemBaslangici': periodStart.toIso8601String(),
    'donemBitisi': periodEnd.toIso8601String(),
    'tutar': amount,
    'odemeTarihi': paidAt.toIso8601String(),
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}

extension PayrollSnapshotSyncExt on PayrollSnapshot {
  Map<String, dynamic> toSyncMap() => {
    'id': id,
    'calisanId': workerId,
    'ay': month,
    'calisilanGunEsdegeri': workedDayEquivalent,
    'brut': gross,
    'kesintiler': deductions,
    'net': net,
    'olusturulmaTarihi': createdAt.toIso8601String(),
    'guncellenmeTarihi': updatedAt.toIso8601String(),
    'silinmeTarihi': deletedAt?.toIso8601String(),
    'sonDegistiren': lastModifiedBy,
    'cihazId': deviceId,
    'senkronSurumu': syncVersion,
  };
}
