import 'package:flutter/material.dart';

import 'design_tokens.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    onPrimary: AppColors.textOnBrand,
    secondary: AppColors.info,
    error: AppColors.danger,
    surface: AppColors.background,
    onSurface: AppColors.textPrimary,
    brightness: Brightness.light,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.pageTitle,
      iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
    ),

    cardTheme: CardThemeData(
      color: AppColors.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
      labelStyle: AppTextStyles.caption,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.textOnBrand,
        textStyle: AppTextStyles.button,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brand,
        textStyle: AppTextStyles.buttonSmall,
        backgroundColor: AppColors.background,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        side: const BorderSide(color: AppColors.brand),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brand,
        textStyle: AppTextStyles.buttonSmall,
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMuted,
      selectedColor: AppColors.brand,
      disabledColor: AppColors.surfaceMuted,
      labelStyle: AppTextStyles.chip.copyWith(color: AppColors.textPrimary),
      secondaryLabelStyle:
          AppTextStyles.chip.copyWith(color: AppColors.textOnBrand),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      side: BorderSide.none,
      showCheckmark: false,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: AppTextStyles.body.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      titleTextStyle: AppTextStyles.cardTitle,
      contentTextStyle: AppTextStyles.body,
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.border),
      ),
      headerBackgroundColor: AppColors.background,
      headerForegroundColor: AppColors.textPrimary,
      headerHeadlineStyle: AppTextStyles.cardTitle.copyWith(fontSize: 22),
      headerHelpStyle: AppTextStyles.caption.copyWith(
        color: AppColors.textTertiary,
        letterSpacing: 0.6,
      ),
      weekdayStyle: AppTextStyles.caption.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
      ),
      dayStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textDisabled;
        }
        if (states.contains(WidgetState.selected)) {
          return AppColors.textOnBrand;
        }
        return AppColors.textPrimary;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.brand;
        }
        return Colors.transparent;
      }),
      dayOverlayColor: WidgetStateProperty.resolveWith(
        (_) => AppColors.brandSurface,
      ),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.textOnBrand;
        }
        return AppColors.brand;
      }),
      todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.brand;
        }
        return Colors.transparent;
      }),
      todayBorder: const BorderSide(color: AppColors.brand, width: 1.4),
      yearStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.textOnBrand;
        }
        return AppColors.textPrimary;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.brand;
        }
        return Colors.transparent;
      }),
      yearOverlayColor: WidgetStateProperty.resolveWith(
        (_) => AppColors.brandSurface,
      ),
      dividerColor: AppColors.border,
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        textStyle: AppTextStyles.button,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: AppColors.brand,
        textStyle: AppTextStyles.button,
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brandSurface,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.brand, size: 22);
        }
        return const IconThemeData(color: AppColors.textTertiary, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTextStyles.caption.copyWith(
            color: AppColors.brand,
            fontWeight: FontWeight.w700,
          );
        }
        return AppTextStyles.caption.copyWith(color: AppColors.textTertiary);
      }),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),

    textTheme: const TextTheme(
      displayLarge: AppTextStyles.metric,
      displayMedium: AppTextStyles.metric,
      headlineLarge: AppTextStyles.pageTitle,
      headlineMedium: AppTextStyles.pageTitle,
      titleLarge: AppTextStyles.cardTitle,
      titleMedium: AppTextStyles.cardTitle,
      titleSmall: AppTextStyles.cardSubtitle,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.body,
      bodySmall: AppTextStyles.caption,
      labelLarge: AppTextStyles.button,
      labelMedium: AppTextStyles.buttonSmall,
      labelSmall: AppTextStyles.sectionLabel,
    ),
  );
}
