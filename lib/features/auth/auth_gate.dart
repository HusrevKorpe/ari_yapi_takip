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
  bool _orgBootstrapInFlight = false;
  String? _orgBootstrapError;

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

  /// Authenticated kullanıcı için organizasyonu garanti eder.
  /// Race condition'ı burada tek noktaya çekiyoruz: LoginPage sadece signIn
  /// yapar, Firestore'daki kullanıcı/organizasyon dokumanlarını AuthGate oluşturur.
  /// Başarısızlık durumunda retry + signOut sunulur.
  Future<void> _ensureOrganization(AuthState state) async {
    if (_orgBootstrapInFlight) return;
    final uid = state.uid;
    if (uid == null || uid.isEmpty) return;

    _orgBootstrapInFlight = true;
    if (_orgBootstrapError != null) {
      setState(() => _orgBootstrapError = null);
    }
    try {
      await ref
          .read(organizationServiceProvider)
          .ensureOrganization(uid: uid, email: state.email);
      // SyncContext'i yeniden hesaplat — ref.listen aşağıda sync'i başlatır.
      ref.invalidate(syncContextProvider);
    } catch (e, st) {
      dev.log(
        'ensureOrganization hatası: $e',
        name: 'AuthGate',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _orgBootstrapError = e.toString());
      }
    } finally {
      _orgBootstrapInFlight = false;
    }
  }

  Future<void> _stopSync() async {
    ref.read(syncServiceProvider).dispose();
    await ref.read(pullSyncServiceProvider).dispose();
    _syncStarted = false;
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (e, st) {
      dev.log('signOut hatası: $e', name: 'AuthGate', error: e, stackTrace: st);
    }
  }

  @override
  void dispose() {
    // _stopSync async olduğundan dispose'da fire-and-forget olarak çalıştırılır.
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
          if (mounted) {
            setState(() {
              _orgBootstrapError = null;
            });
          }
          ref.invalidate(syncContextProvider);
        });
      });
    });

    // ensureOrganization sonrası ctx geçerli olduğunda sync başlatılır.
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
            return const LoginPage();
          case AuthStatus.authenticated:
            final ctx = ref.read(syncContextProvider);

            if (ctx.isValid) {
              if (!_syncStarted) _startSync(ctx);
              return widget.child;
            }

            // Authenticated ama organizasyon bağlamı yok — bootstrap et.
            // Bu kapsar: ilk login, önceki hatalı ensureOrganization, eksik prefs.
            if (_orgBootstrapError == null && !_orgBootstrapInFlight) {
              Future.microtask(() => _ensureOrganization(state));
            }

            if (_orgBootstrapError != null) {
              return _BootstrapErrorScreen(
                message: _orgBootstrapError!,
                onRetry: () => _ensureOrganization(state),
                onSignOut: _signOut,
              );
            }

            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Oturum hazırlanıyor...'),
                  ],
                ),
              ),
            );
        }
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: Center(child: Text('Auth hatasi'))),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Organizasyon yüklenemedi',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF666666)),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tekrar Dene'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Çıkış Yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
