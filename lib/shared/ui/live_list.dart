import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Bir liste ekranı için "snapshot + güncelleme banner'ı + pull-to-refresh"
/// davranışı sunar.
///
/// - Sayfa ilk açıldığında akıştan gelen ilk veri snapshot olarak dondurulur;
///   sonraki yayımlar UI'yı otomatik tazelemez.
/// - Uzaktan gelen değişiklikler (başka cihazdan senkron) tespit edilince
///   üstte "X güncelleme var - Göster" banner'ı çıkar. Kullanıcı dokununca
///   snapshot güncellenir.
/// - Yerel değişiklikler (kullanıcının kendi eklediği/sildiği öğeler)
///   pendingSyncCount > 0 ile tespit edilir ve snapshot otomatik güncellenir —
///   böylece kullanıcı kendi aksiyonunun sonucunu anında görür.
/// - Kaydırarak aşağı çekme (RefreshIndicator) builder'a verilen [onRefresh]
///   callback'i üzerinden callerd'a bırakılır.
class LiveList<T> extends ConsumerStatefulWidget {
  const LiveList({
    super.key,
    required this.async,
    required this.idOf,
    required this.builder,
    this.resetKey,
    this.loadingBuilder,
    this.errorBuilder,
    this.bannerColor = const Color(0xFFFFF5D6),
    this.bannerForegroundColor = const Color(0xFF8A7300),
    this.bannerTextColor = const Color(0xFF4F472A),
  });

  final AsyncValue<List<T>> async;
  final Object Function(T item) idOf;

  /// builder(context, snapshot, onRefresh). onRefresh push-to-refresh için
  /// RefreshIndicator.onRefresh'e bağlanmalıdır.
  final Widget Function(
    BuildContext context,
    List<T> snapshot,
    Future<void> Function() onRefresh,
  ) builder;

  /// Değiştiğinde snapshot sıfırlanır (ör. ay/tarih filtresi değişince).
  final Object? resetKey;

  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  final Color bannerColor;
  final Color bannerForegroundColor;
  final Color bannerTextColor;

  @override
  ConsumerState<LiveList<T>> createState() => _LiveListState<T>();
}

class _LiveListState<T> extends ConsumerState<LiveList<T>> {
  List<T>? _snapshot;
  Object? _lastResetKey;

  @override
  void initState() {
    super.initState();
    _lastResetKey = widget.resetKey;
    _snapshot = widget.async.valueOrNull;
  }

  Future<void> _onRefresh() async {
    try {
      await ref.read(syncServiceProvider).flushPending();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final latest = widget.async.valueOrNull;
    if (latest == null) return;
    setState(() => _snapshot = latest);
  }

  void _applyLatest() {
    final latest = widget.async.valueOrNull;
    if (latest == null) return;
    setState(() => _snapshot = latest);
  }

  int _diffCount(List<T> snap, List<T> latest) {
    final snapMap = <Object, T>{for (final e in snap) widget.idOf(e): e};
    final latestMap = <Object, T>{for (final e in latest) widget.idOf(e): e};
    var count = 0;
    for (final entry in latestMap.entries) {
      final old = snapMap[entry.key];
      if (old == null || old != entry.value) count++;
    }
    for (final id in snapMap.keys) {
      if (!latestMap.containsKey(id)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final latest = widget.async.valueOrNull;

    if (widget.resetKey != _lastResetKey) {
      _lastResetKey = widget.resetKey;
      _snapshot = latest;
    } else if (_snapshot == null && latest != null) {
      _snapshot = latest;
    } else if (_snapshot != null &&
        latest != null &&
        pendingCount > 0 &&
        !listEquals(_snapshot, latest)) {
      _snapshot = latest;
    }

    final snap = _snapshot;
    if (snap == null) {
      return widget.async.when(
        data: (data) => widget.builder(context, data, _onRefresh),
        loading: () =>
            widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            widget.errorBuilder?.call(context, error) ??
            Center(child: Text(error.toString())),
      );
    }

    final remoteCount = (latest != null && pendingCount == 0)
        ? _diffCount(snap, latest)
        : 0;

    return Column(
      children: [
        if (remoteCount > 0)
          _UpdatesBanner(
            count: remoteCount,
            onApply: _applyLatest,
            background: widget.bannerColor,
            foreground: widget.bannerForegroundColor,
            textColor: widget.bannerTextColor,
          ),
        Expanded(child: widget.builder(context, snap, _onRefresh)),
      ],
    );
  }
}

class _UpdatesBanner extends StatelessWidget {
  const _UpdatesBanner({
    required this.count,
    required this.onApply,
    required this.background,
    required this.foreground,
    required this.textColor,
  });

  final int count;
  final VoidCallback onApply;
  final Color background;
  final Color foreground;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: InkWell(
        onTap: onApply,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count yeni guncelleme var',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'Goster',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: foreground,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 18, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
