import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../partner_payments/partner_payments_page.dart';
import 'expenses_page.dart';

/// Alt menüdeki "Gider" sekmesi altında iki defter barındırır:
/// klasik giderler ve ortağa verilen ödemeler. Ortak ödemeleri gidere
/// karışmaz — kendi tablosu, toplamı ve listesi vardır.
class ExpensesTabsPage extends StatelessWidget {
  const ExpensesTabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const TabBar(
            labelColor: AppColors.brandDark,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.brand,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'Giderler'),
              Tab(text: 'Ortak'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ExpensesPage(),
            PartnerPaymentsPage(),
          ],
        ),
      ),
    );
  }
}
