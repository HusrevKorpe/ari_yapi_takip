import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'data/local/local_preferences.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase config bulunmazsa uygulama local-first modda calisir.
  }

  await initializeDateFormatting('tr_TR');

  final prefs = await SharedPreferences.getInstance();
  final localPrefs = LocalPreferences(prefs);
  await localPrefs.ensureDeviceId(const Uuid());

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AriApp(),
    ),
  );
}
