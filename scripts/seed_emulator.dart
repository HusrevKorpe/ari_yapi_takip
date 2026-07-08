// Emulator seed: her Auth kullanicisi icin users/{uid}.organizationId ve
// organizations/{uid} dokumanlarini olusturur.
//
// NEDEN GEREKLI: firestore.rules, client'in users/{uid}.organizationId yazmasini
// bilerek yasaklar (capraz-kiraci yetki yukseltmesine karsi). Bu yuzden uygulama
// bu alani asla yazmaz, yalnizca okur. Production'da alan Console/Admin ile
// atanir; emulator'da da bu script Admin (owner) yetkisiyle atar.
//
// GUVENLIK:
//   * SADECE localhost emulator'a (127.0.0.1:8080/9099) yazar. Production'a
//     dokunmaz — `Authorization: Bearer owner` yalnizca emulator'in kabul ettigi
//     bir token'dir; canli Firebase onu reddeder.
//   * IDEMPOTENT ve YIKICI DEGIL: hicbir sey silmez. Doküman zaten varsa dokunmaz;
//     users icin yalnizca `organizationId` alanini ekler (updateMask), diger
//     alanlar korunur.
//
// KULLANIM (once ./scripts/emulator.sh calisiyor ve uygulamada en az bir kez
// giris yapilmis olmali):
//   dart run scripts/seed_emulator.dart
//   SEED_ORG_ID=<admin1_uid> dart run scripts/seed_emulator.dart  # hepsini tek org'a bagla
//
// Ortam degiskenleri (opsiyonel): EMULATOR_HOST, FIREBASE_PROJECT,
// EMULATOR_AUTH_PORT, EMULATOR_FIRESTORE_PORT, SEED_ORG_ID.

import 'dart:convert';
import 'dart:io';

const _defaultProject = 'ari-yapi-takip';

String _env(String key, String fallback) {
  final v = Platform.environment[key];
  return (v == null || v.isEmpty) ? fallback : v;
}

Future<void> main(List<String> args) async {
  final host = _env('EMULATOR_HOST', '127.0.0.1');
  final projectId = _env('FIREBASE_PROJECT', _defaultProject);
  final authPort = int.parse(_env('EMULATOR_AUTH_PORT', '9099'));
  final firestorePort = int.parse(_env('EMULATOR_FIRESTORE_PORT', '8080'));
  final forcedOrgId = Platform.environment['SEED_ORG_ID']; // opsiyonel

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  // 0) Preflight: yanlislikla production'a yazmayi imkansiz kilmak icin once
  // localhost emulator gercekten ayakta mi diye bak.
  try {
    final socket = await Socket.connect(
      host,
      firestorePort,
      timeout: const Duration(seconds: 3),
    );
    socket.destroy();
  } catch (_) {
    stderr.writeln(
      'HATA: Firestore emulator $host:$firestorePort adresinde calismiyor.\n'
      'Once baska bir terminalde ./scripts/emulator.sh ile emulator\'i baslatin.',
    );
    exit(1);
  }

  try {
    // 1) Emulator Auth'taki kullanicilari listele.
    final accounts = await _listAccounts(client, host, authPort, projectId);
    if (accounts.isEmpty) {
      stdout.writeln(
        'Emulator Auth\'ta hic kullanici yok. Once uygulamada kaydolun/giris '
        'yapin, sonra bu script\'i tekrar calistirin.',
      );
      return;
    }

    stdout.writeln('${accounts.length} kullanici bulundu. Seed basliyor...\n');
    if (forcedOrgId != null && forcedOrgId.isNotEmpty) {
      stdout.writeln('Tum kullanicilar tek org\'a baglaniyor: $forcedOrgId\n');
    }

    final seededOrgs = <String>{};
    var written = 0;
    var skipped = 0;

    for (final acc in accounts) {
      final uid = acc['localId'] as String;
      final email = acc['email'] as String?;
      final orgId = (forcedOrgId != null && forcedOrgId.isNotEmpty)
          ? forcedOrgId
          : uid;

      // users/{uid}.organizationId
      final existing = await _getDoc(
        client,
        host,
        firestorePort,
        projectId,
        'users/$uid',
      );
      final existingOrg =
          existing?['fields']?['organizationId']?['stringValue'];
      if (existingOrg == orgId) {
        stdout.writeln('•  users/$uid → zaten organizationId=$orgId (atlandi)');
        skipped++;
      } else {
        await _patchDoc(
          client,
          host,
          firestorePort,
          projectId,
          'users/$uid',
          {
            'organizationId': {'stringValue': orgId},
          },
          const ['organizationId'],
        );
        stdout.writeln(
          '✓  users/$uid → organizationId=$orgId'
          '${email != null ? '  ($email)' : ''}',
        );
        written++;
      }

      // organizations/{orgId} — yoksa olustur (org sahibi = orgId).
      if (seededOrgs.add(orgId)) {
        final org = await _getDoc(
          client,
          host,
          firestorePort,
          projectId,
          'organizations/$orgId',
        );
        if (org == null) {
          await _patchDoc(
            client,
            host,
            firestorePort,
            projectId,
            'organizations/$orgId',
            {
              'id': {'stringValue': orgId},
              'ownerUid': {'stringValue': orgId},
              'email': email != null
                  ? {'stringValue': email}
                  : {'nullValue': null},
              'createdAt': {'stringValue': DateTime.now().toIso8601String()},
            },
            const ['id', 'ownerUid', 'email', 'createdAt'],
          );
          stdout.writeln('✓  organizations/$orgId → olusturuldu');
        } else {
          stdout.writeln('•  organizations/$orgId → zaten var (atlandi)');
        }
      }
    }

    stdout.writeln(
      '\nBitti. $written yazildi, $skipped atlandi. '
      'Uygulamada "Tekrar Dene" deyin ya da yeniden giris yapin.',
    );
  } finally {
    client.close();
  }
}

/// Emulator Auth'taki tum hesaplari doner. `Bearer owner` yalnizca emulator'da
/// admin yetkisi verir.
Future<List<Map<String, dynamic>>> _listAccounts(
  HttpClient client,
  String host,
  int port,
  String projectId,
) async {
  final uri = Uri.parse(
    'http://$host:$port/identitytoolkit.googleapis.com/v1/'
    'projects/$projectId/accounts:query',
  );
  final req = await client.postUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(const <String, dynamic>{}));
  final res = await req.close();
  final body = await utf8.decoder.bind(res).join();
  if (res.statusCode != 200) {
    throw StateError('Auth listeleme basarisiz (${res.statusCode}): $body');
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final list = (decoded['userInfo'] as List?) ?? const [];
  return list.cast<Map<String, dynamic>>();
}

String _docUrl(String host, int port, String projectId, String path) =>
    'http://$host:$port/v1/projects/$projectId/databases/(default)/documents/$path';

/// Dokumani okur; yoksa null doner.
Future<Map<String, dynamic>?> _getDoc(
  HttpClient client,
  String host,
  int port,
  String projectId,
  String path,
) async {
  final req = await client.getUrl(
    Uri.parse(_docUrl(host, port, projectId, path)),
  );
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  final res = await req.close();
  final body = await utf8.decoder.bind(res).join();
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) {
    throw StateError('GET $path basarisiz (${res.statusCode}): $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

/// Yalnizca `mask`'teki alanlari yazar (digerlerini silmez/degistirmez).
/// Doküman yoksa PATCH onu olusturur.
Future<void> _patchDoc(
  HttpClient client,
  String host,
  int port,
  String projectId,
  String path,
  Map<String, dynamic> fields,
  List<String> mask,
) async {
  final maskQuery = mask.map((f) => 'updateMask.fieldPaths=$f').join('&');
  final uri = Uri.parse('${_docUrl(host, port, projectId, path)}?$maskQuery');
  final req = await client.patchUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode({'fields': fields}));
  final res = await req.close();
  final body = await utf8.decoder.bind(res).join();
  if (res.statusCode != 200) {
    throw StateError('PATCH $path basarisiz (${res.statusCode}): $body');
  }
}
