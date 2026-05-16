import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Bir liste ekranı için "snapshot + pull-to-refresh" davranışı sunar.
///
/// - Sayfa ilk açıldığında akıştan gelen ilk veri snapshot olarak alınır;
///   sonraki yayımlar UI'yı otomatik tazeler (yerel veya uzak fark etmez).
/// - Kaydırarak aşağı çekme (RefreshIndicator) builder'a verilen [onRefresh]
///   callback'i üzerinden caller'a bırakılır.
class LiveList<T> extends ConsumerStatefulWidget {
  const LiveList({
    super.key,
    required this.async,
    required this.idOf,
    required this.builder,
    this.resetKey,
    this.loadingBuilder,
    this.errorBuilder,
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

  @override
  Widget build(BuildContext context) {
    final latest = widget.async.valueOrNull;

    if (widget.resetKey != _lastResetKey) {
      _lastResetKey = widget.resetKey;
      _snapshot = latest;
    } else if (latest != null) {
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

    return widget.builder(context, snap, _onRefresh);
  }
}
