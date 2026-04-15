/// Firestore entity type → koleksiyon adı eşlemesi.
/// Hem push (FirebaseRemoteDataSource) hem pull (PullSyncService) kullanır.
const kEntityCollections = <String, String>{
  'worker': 'calisanlar',
  'site': 'santiyeler',
  'attendance': 'yoklama',
  'expense': 'giderler',
  'income': 'gelirler',
  'advance_debt': 'avans_borclar',
  'payroll_payment': 'maas_odemeleri',
  'payroll_snapshot': 'maas_ozetleri',
};
