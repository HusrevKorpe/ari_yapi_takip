import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'data/local/local_preferences.dart';
import 'firebase_options.dart';

/// `--dart-define=USE_EMULATOR=true` ile derlendiginde uygulama canli Firebase
/// yerine yerel Firebase Emulator Suite'e baglanir. Boylece test sirasinda
/// production verisine (ari-yapi-takip) dokunulmaz.
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// Emulator host'unu elle ezmek icin: `--dart-define=EMULATOR_HOST=192.168.1.x`
/// (gercek Android/iOS cihazda makinenin LAN IP'sini ver). Bos birakilirsa
/// platforma gore otomatik secilir.
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST');

void main() {
  // Tum uygulama tek bir hata bolgesi (zone) icinde calisir; boylece
  // async gap'lerde kacan hatalar da yakalanir.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Framework ve platform kaynakli yakalanmamis hatalari tek noktaya topla.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _reportFatalError(
          details.exception,
          details.stack,
          source: 'FlutterError',
        );
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        _reportFatalError(error, stack, source: 'PlatformDispatcher');
        return true;
      };

      var firebaseReady = false;
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseReady = true;
      } catch (_) {
        // Firebase config bulunmazsa uygulama local-first modda calisir.
      }

      if (firebaseReady && _useEmulator) {
        await _connectToEmulators();
      }

      await initializeDateFormatting('tr_TR');

      final prefs = await SharedPreferences.getInstance();
      final localPrefs = LocalPreferences(prefs);
      await localPrefs.ensureDeviceId(const Uuid());

      // Mevcut kurulumlar icin kalici "yerel DB hangi org'a ait" isaretini bir
      // kez geriye donuk doldur: cihaz zaten bir org'a bagliysa ve isaret bos
      // ise mevcut org ile esitle. Boylece ilk cikis-sonrasi hesap degisiminde
      // de yerel veri temizligi dogru tetiklenir (capraz-org sizintisi).
      if (localPrefs.localDataOrganizationId.isEmpty &&
          localPrefs.organizationId.isNotEmpty) {
        await localPrefs.setLocalDataOrganizationId(localPrefs.organizationId);
      }

      runApp(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const AriApp(),
        ),
      );
    },
    (error, stack) =>
        _reportFatalError(error, stack, source: 'runZonedGuarded'),
  );
}

/// Yakalanmamis tum hatalar buraya duser. Su an yerel log'a yaziyor;
/// Crashlytics eklendiginde `FirebaseCrashlytics.instance.recordError(...)`
/// cagrisi da tam olarak buraya baglanir.
void _reportFatalError(
  Object error,
  StackTrace? stack, {
  required String source,
}) {
  developer.log(
    'Yakalanmamis hata [$source]: $error',
    name: 'ari_yapi_takip',
    error: error,
    stackTrace: stack,
  );
}

/// Firestore ve Auth'u yerel Emulator Suite'e yonlendirir.
Future<void> _connectToEmulators() async {
  // Android emulatorde host makineye 10.0.2.2 ile erisilir; diger
  // platformlarda (iOS sim, macOS, web, desktop) localhost yeterli.
  final host = _emulatorHost.isNotEmpty
      ? _emulatorHost
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? '10.0.2.2'
          : 'localhost');

  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);

  debugPrint(
    '🔧 Firebase EMULATOR aktif → $host '
    '(Firestore:8080, Auth:9099, UI:4000). Production verisine dokunulmuyor.',
  );
}
