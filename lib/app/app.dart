import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../features/attendance/attendance_page.dart';
import '../features/auth/auth_gate.dart';
import '../features/expenses/expenses_page.dart';
import '../features/incomes/incomes_page.dart';
import '../features/payroll/payroll_page.dart';
import '../features/sites/sites_page.dart';
import '../features/workers/workers_page.dart';
import '../shared/snackbar_helper.dart';
import 'splash_page.dart';
import 'theme.dart';

class AriApp extends ConsumerStatefulWidget {
  const AriApp({super.key});

  @override
  ConsumerState<AriApp> createState() => _AriAppState();
}

class _AriAppState extends ConsumerState<AriApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arı Saha Yonetim',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AriSplashPage(
        child: _DatabaseGate(child: AuthGate(child: RootShell())),
      ),
    );
  }
}

/// Migration başarısız olursa DB'ye bağımlı tüm akış (AuthGate dahil) sessizce
/// hata fırlatırdı — provider'lar lazy olduğundan splash "sonsuza kadar"
/// görünürdü. Bu gate warmUp future'ını izleyip kullanıcıya anlamlı bir
/// hata ekranı sunar; aksi halde child'a geçer.
class _DatabaseGate extends ConsumerWidget {
  const _DatabaseGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warmUp = ref.watch(databaseWarmUpProvider);
    return warmUp.when(
      data: (_) => child,
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _DatabaseErrorScreen(
        message: e.toString(),
        onRetry: () => ref.invalidate(databaseWarmUpProvider),
      ),
    );
  }
}

class _DatabaseErrorScreen extends StatelessWidget {
  const _DatabaseErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
                const Icon(Icons.storage_rounded,
                    size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Veritabanı güncellenemedi',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Uygulama yeni sürüme hazırlanırken bir sorun oluştu. '
                  'Lütfen tekrar deneyin; sorun sürerse destekle iletişime geçin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF666666)),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFB5390F)),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;
  static const _tabItems = <({IconData icon, String label})>[
    (icon: Icons.people_alt_rounded, label: 'Calisanlar'),
    (icon: Icons.fact_check_outlined, label: 'Yoklama'),
    (icon: Icons.receipt_long_rounded, label: 'Gider'),
    (icon: Icons.trending_up_rounded, label: 'Gelir'),
    (icon: Icons.payments_rounded, label: 'Maas'),
    (icon: Icons.location_city_rounded, label: 'Santiyeler'),
  ];

  static const _pages = [
    WorkersPage(),
    AttendancePage(),
    ExpensesPage(),
    IncomesPage(),
    PayrollPage(),
    SitesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final failedCount = ref.watch(failedPermanentCountProvider).maybeWhen(
          data: (v) => v,
          orElse: () => 0,
        );

    return Scaffold(
      body: Column(
        children: [
          if (failedCount > 0) _SyncFailureBanner(count: failedCount),
          Expanded(child: _pages[_index]),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEAEAEA))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: List.generate(_tabItems.length, (tabIndex) {
                final isSelected = _index == tabIndex;
                final item = _tabItems[tabIndex];

                return Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _index = tabIndex),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: isSelected
                              ? const Color(0xFF8A7300)
                              : const Color(0xFFAAAAAA),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFF8A7300)
                                : const Color(0xFFAAAAAA),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncFailureBanner extends ConsumerWidget {
  const _SyncFailureBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: const Color(0xFFFFF4E5),
      child: InkWell(
        onTap: () => _showDetails(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.sync_problem_rounded,
                color: Color(0xFFC05621),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count kayıt senkronize edilemedi — dokunarak incele',
                  style: const TextStyle(
                    color: Color(0xFF7A3E0F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF7A3E0F),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(syncQueueRepositoryProvider);
    final items = await repo.failedPermanentItems();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Senkronize edilemeyen kayıtlar'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 12),
            itemBuilder: (context, i) {
              final it = items[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${it.entityType} / ${it.action}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'id: ${it.entityId}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (it.lastError != null && it.lastError!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      it.lastError!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB5390F),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () async {
              // Orphan (orgId boş) öğeleri önce mevcut orgId ile tamir et;
              // aksi halde retryFailedPermanent onları boş orgId ile pending'e
              // döndürür ve bir sonraki flush'ta yine markAbandoned'a düşerler.
              final orgId =
                  ref.read(syncContextProvider).organizationId;
              if (orgId.isEmpty) {
                if (context.mounted) {
                  showErrorSnackBar(
                    context,
                    'Oturum bilgisi yüklenmedi — lütfen yeniden giriş yapın.',
                  );
                }
                return;
              }
              await repo.backfillOrgId(orgId);
              await repo.retryFailedPermanent();
              if (context.mounted) Navigator.of(context).pop();
              ref.read(syncServiceProvider).flushPending();
            },
            child: const Text('Tümünü Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}
