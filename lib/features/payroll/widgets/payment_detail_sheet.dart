import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';
import 'cancel_payment_dialog.dart';
import 'day_detail_expander.dart';
import 'payroll_shared.dart';

Future<void> showPaymentDetailSheet(
  BuildContext context,
  PayrollPayment payment,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PaymentDetailSheet(payment: payment),
  );
}

class _PaymentDetailSheet extends ConsumerWidget {
  const _PaymentDetailSheet({required this.payment});

  final PayrollPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(_paymentSnapshotProvider(payment));
    final daysAsync = ref.watch(paymentBreakdownProvider(payment));

    // İptal yalnızca en son (periodEnd'i en büyük) ödemeye izinli. Aradaki bir
    // ödemeyi iptal etmek o dönemi erişilemez kılar; repository de bunu guard
    // ile reddediyor, burada butonu baştan gizliyoruz. Liste henüz gelmediyse
    // buton gösterilmez (güvenli varsayım) — repository yine korur.
    final payments = ref.watch(workerPaymentsProvider(payment.workerId));
    final isLatest = payments.maybeWhen(
      data: (list) => !list.any(
        (p) => p.id != payment.id && p.periodEnd.isAfter(payment.periodEnd),
      ),
      orElse: () => false,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCCCCCC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: snapshotAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Hata: $e'),
              ),
              data: (snapshot) => _DetailBody(
                payment: payment,
                snapshot: snapshot,
                breakdown: daysAsync.asData?.value,
                breakdownReady: daysAsync.hasValue,
                canCancel: isLatest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eski ödemede (donmuş döküm yokken) ödeme anına göre yeniden kurulan döküm
/// için not. Liste, ödeme yapıldığı ana kadar girilmiş günlerden oluşur ve
/// üstteki donmuş özetle uyumludur; kullanıcı kaynağını bu notla anlar.
class _LiveBreakdownNote extends StatelessWidget {
  const _LiveBreakdownNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCDCDD)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.history_rounded,
            size: 18,
            color: Color(0xFF888888),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bu eski ödemede günlük döküm ayrıca saklanmamıştı; aşağıdaki '
              'liste ödemenin yapıldığı ana kadar girilmiş puantajdan yeniden '
              'oluşturuldu ve yukarıdaki özetle uyumludur. (Ödemeden sonra o '
              'döneme girilen günler burada görünmez; onlar sonraki döneme / '
              'bakiyeye devreder.)',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Color(0xFF6E6E6E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eski ödeme için ne donmuş döküm var ne de güncel puantajdan gün üretilebildi
/// (ör. çalışan silinmiş). Bu durumda yalnızca yukarıdaki özet gösterilebilir.
class _BreakdownUnavailableNote extends StatelessWidget {
  const _BreakdownUnavailableNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCDCDD)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: Color(0xFF888888),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bu eski ödeme için günlük döküm bulunamadı. Yukarıdaki özet, '
              'ödemenin yapıldığı andaki değerleri gösterir.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Color(0xFF6E6E6E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _paymentSnapshotProvider = FutureProvider.autoDispose
    .family<PayrollSnapshot?, PayrollPayment>((ref, payment) {
  return ref.watch(payrollRepositoryProvider).getSnapshot(
        workerId: payment.workerId,
        periodStart: payment.periodStart,
        periodEnd: payment.periodEnd,
      );
});

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.payment,
    required this.snapshot,
    required this.breakdown,
    required this.breakdownReady,
    required this.canCancel,
  });

  final PayrollPayment payment;
  final PayrollSnapshot? snapshot;
  // Günlük döküm + kaynağı (donmuş / canlı). null = sağlayıcı henüz yüklenmedi.
  final PaymentBreakdown? breakdown;
  // Döküm sağlayıcısı yüklendi mi? Yüklenirken not/döküm gösterme (titreme olmasın).
  final bool breakdownReady;
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      children: [
        Text(
          'Ödeme Detayı',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A1A),
              ),
        ),
        const SizedBox(height: 18),
        PayrollSummaryRow(
          label: 'Dönem',
          value:
              '${formatDate(payment.periodStart)} – ${formatDate(payment.periodEnd)}',
        ),
        const SizedBox(height: 12),
        PayrollSummaryRow(
          label: 'Ödeme Tarihi',
          value: formatDate(payment.paidAt),
        ),
        const SizedBox(height: 12),
        PayrollSummaryRow(
          label: 'Ödenen Tutar',
          value: formatMoney(payment.amount),
          valueColor: const Color(0xFF1A6B5A),
        ),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFDCDCDD)),
          const SizedBox(height: 12),
          PayrollSummaryRow(
            label: 'Çalışılan Gün',
            value: formatWorkedDays(snapshot!.workedDayEquivalent),
          ),
          const SizedBox(height: 12),
          PayrollSummaryRow(
            label: 'Brut',
            value: formatMoney(snapshot!.gross),
          ),
          const SizedBox(height: 12),
          if (snapshot!.deductions < 0)
            // Eski ödemelerde (borç kaydı henüz varken donmuş) kesinti negatif
            // olabilir; net'i artıran bu tutarı "Kesinti" gibi göstermeyip ayrı
            // bir "Alacak" satırı veriyoruz.
            PayrollSummaryRow(
              label: 'Alacak',
              value: '+${formatMoney(-snapshot!.deductions)}',
              valueColor: const Color(0xFF1A6B5A),
            )
          else
            PayrollSummaryRow(
              label: 'Kesinti',
              value: formatMoney(snapshot!.deductions),
              valueColor: const Color(0xFFB60A0A),
            ),
          const SizedBox(height: 12),
          PayrollSummaryRow(
            label: 'Net',
            value: formatMoney(snapshot!.net),
            valueColor: const Color(0xFF1A6B5A),
          ),
        ],
        if (breakdownReady && breakdown != null && breakdown!.days.isNotEmpty) ...[
          // Canlı yeniden hesaplanmış dökümde, özetle çelişebileceği uyarısı
          // önce gelsin ki kullanıcı listeyi doğru okusun.
          if (!breakdown!.isFrozen) ...[
            const SizedBox(height: 16),
            const _LiveBreakdownNote(),
          ],
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCDCDD)),
            ),
            child: DayDetailExpander(days: breakdown!.days),
          ),
        ],
        // Ne donmuş döküm var ne de güncel puantajdan gün üretilebildi
        // (ör. çalışan silinmiş): yalnızca özet gösterilebilir.
        if (breakdownReady && breakdown != null && breakdown!.days.isEmpty) ...[
          const SizedBox(height: 16),
          const _BreakdownUnavailableNote(),
        ],
        const SizedBox(height: 24),
        if (canCancel)
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB60A0A),
                side: const BorderSide(color: Color(0xFFFF5252)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => cancelPaymentFlow(context, payment),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text(
                'Ödemeyi İptal Et',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDCDCDD)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFF888888),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bu ödeme iptal edilemez. Yalnızca en son ödeme iptal '
                    'edilebilir; önce daha sonraki dönemlerin ödemelerini iptal '
                    'edin.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Color(0xFF6E6E6E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
