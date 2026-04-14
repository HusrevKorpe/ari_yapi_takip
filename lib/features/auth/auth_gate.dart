import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/auth/auth_state.dart';
import '../../data/sync/sync_context.dart';
import 'login_page.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _syncStarted = false;

  void _startSync(SyncContext ctx) {
    _syncStarted = true;
    Future.microtask(() async {
      try {
        await ref.read(bootstrapServiceProvider).run(ctx);
        final syncService = ref.read(syncServiceProvider);
        syncService.startConnectivityWatch();
        await syncService.flushPending();
        await ref.read(pullSyncServiceProvider).start(ctx.organizationId);
      } catch (e, st) {
        dev.log(
          'Sync başlatma hatası: $e',
          name: 'AuthGate',
          error: e,
          stackTrace: st,
        );
        _syncStarted = false;
      }
    });
  }

  Future<void> _stopSync() async {
    ref.read(syncServiceProvider).dispose();
    await ref.read(pullSyncServiceProvider).dispose();
    _syncStarted = false;
  }

  @override
  void dispose() {
    // _stopSync async olduğundan dispose'da fire-and-forget olarak çalıştırılır.
    // Widget ağacından çıkışta abonelikler iptal edilir; kısa bir gecikme kabul edilebilir.
    if (_syncStarted) {
      ref.read(syncServiceProvider).dispose();
      ref.read(pullSyncServiceProvider).dispose();
      _syncStarted = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    ref.listen<AsyncValue<AuthState>>(authStateProvider, (_, next) {
      next.whenData((state) {
        if (state.status != AuthStatus.unauthenticated) return;
        Future.microtask(() async {
          if (_syncStarted) await _stopSync();
          await ref.read(localPreferencesProvider).clearSession();
          ref.invalidate(syncContextProvider);
        });
      });
    });

    // İlk login race condition'ı: Firebase auth state, ensureOrganization
    // tamamlanmadan önce tetiklenebilir. ctx o anda geçersizdir.
    // LoginPage'de ensureOrganization sonrası invalidate edilen
    // syncContextProvider geçerli değere gelince burada sync başlatılır.
    ref.listen<SyncContext>(syncContextProvider, (_, ctx) {
      if (!_syncStarted && ctx.isValid) {
        _startSync(ctx);
      }
    });

    return authState.when(
      data: (state) {
        switch (state.status) {
          case AuthStatus.unknown:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.unauthenticated:
            // Logout akışı ref.listen tarafından async olarak yönetilir.
            return const LoginPage();
          case AuthStatus.authenticated:
            if (!_syncStarted) {
              final ctx = ref.read(syncContextProvider);
              if (ctx.isValid) {
                // ctx zaten geçerli (sonraki uygulama açılışları)
                _startSync(ctx);
              }
              // ctx henüz geçersizse (ilk login) ref.listen yukarıda yakalar
            }
            return widget.child;
        }
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: Center(child: Text('Auth hatasi'))),
    );
  }
}
