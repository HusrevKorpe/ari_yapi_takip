import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Drift migration lazy olduğundan provider oluşurken hata yakalanmaz;
/// uygulama açılışında bu provider migration'u zorla tetikleyip hatayı
/// UI'a taşır. AuthGate/AriApp bu future'ı izleyip fail durumunda kullanıcıya
/// görünür bir ekran sunar.
final databaseWarmUpProvider = FutureProvider<void>((ref) {
  return ref.watch(databaseProvider).warmUp();
});

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());
