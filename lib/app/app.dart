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
import 'design_tokens.dart';
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
      title: 'Arı Saha Yönetim',
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
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Veritabanı güncellenemedi',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.cardTitle,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Uygulama yeni sürüme hazırlanırken bir sorun oluştu. '
                  'Lütfen tekrar deneyin; sorun sürerse destekle iletişime geçin.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
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

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.people_alt_outlined),
      selectedIcon: Icon(Icons.people_alt_rounded),
      label: 'Çalışan',
    ),
    NavigationDestination(
      icon: Icon(Icons.fact_check_outlined),
      selectedIcon: Icon(Icons.fact_check_rounded),
      label: 'Yoklama',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Gider',
    ),
    NavigationDestination(
      icon: Icon(Icons.trending_up_outlined),
      selectedIcon: Icon(Icons.trending_up_rounded),
      label: 'Gelir',
    ),
    NavigationDestination(
      icon: Icon(Icons.payments_outlined),
      selectedIcon: Icon(Icons.payments_rounded),
      label: 'Maaş',
    ),
    NavigationDestination(
      icon: Icon(Icons.location_city_outlined),
      selectedIcon: Icon(Icons.location_city_rounded),
      label: 'Şantiye',
    ),
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
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: _destinations,
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
      color: AppColors.warningLight,
      child: InkWell(
        onTap: () => _showDetails(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.sync_problem_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$count kayıt senkronize edilemedi — dokunarak incele',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.warning,
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

