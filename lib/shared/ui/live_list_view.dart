import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import 'live_list.dart';

/// Pull-to-refresh + boş durum + ayrıştırılmış liste kalıbı için sarmalayıcı.
///
/// `LiveList`'i sarar; öğe yokken [emptyState]'i kaydırılabilir bir liste
/// içinde gösterir, doluyken [itemBuilder] ile `ListView.separated` üretir.
class LiveListView<T> extends StatelessWidget {
  const LiveListView({
    super.key,
    required this.async,
    required this.idOf,
    required this.itemBuilder,
    required this.emptyState,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.xxxl,
    ),
    this.separator = const SizedBox(height: AppSpacing.sm),
    this.emptyTopGap = 120,
    this.resetKey,
  });

  final AsyncValue<List<T>> async;
  final Object Function(T item) idOf;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget emptyState;
  final EdgeInsets padding;
  final Widget separator;
  final double emptyTopGap;
  final Object? resetKey;

  @override
  Widget build(BuildContext context) {
    return LiveList<T>(
      async: async,
      idOf: idOf,
      resetKey: resetKey,
      builder: (context, items, onRefresh) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: emptyTopGap),
                    emptyState,
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: padding,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => separator,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, items[index]),
                ),
        );
      },
    );
  }
}
