import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/attendance/attendance_page.dart';
import '../features/auth/auth_gate.dart';
import '../features/expenses/expenses_page.dart';
import '../features/payroll/payroll_page.dart';
import '../features/sites/sites_page.dart';
import '../features/workers/workers_page.dart';
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
      title: 'Ari Yapi Yonetim',
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
        child: AuthGate(child: RootShell()),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  static const _tabItems = <({IconData icon, String label})>[
    (icon: Icons.people_alt_rounded, label: 'Calisanlar'),
    (icon: Icons.fact_check_outlined, label: 'Yoklama'),
    (icon: Icons.receipt_long_rounded, label: 'Gider'),
    (icon: Icons.payments_rounded, label: 'Maas'),
    (icon: Icons.location_city_rounded, label: 'Santiyeler'),
  ];

  static const _pages = [
    WorkersPage(),
    AttendancePage(),
    ExpensesPage(),
    PayrollPage(),
    SitesPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
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
