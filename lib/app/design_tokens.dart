import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılan renk, boşluk, yarıçap, gölge, tipografi
/// sabitleri. Hard-coded renk/sayı kullanmak yerine bu sınıflara referans ver.
/// Yeni bir rengin/spacing'in burada karşılığı yoksa önce buraya ekle.

class AppColors {
  const AppColors._();

  // Marka — altın
  static const Color brand = Color(0xFF8A7300);
  static const Color brandLight = Color(0xFFD6B100);
  static const Color brandDark = Color(0xFF5C4D00);
  static const Color brandSurface = Color(0xFFFFF7DB);

  // Anlamsal
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE6F4EA);
  static const Color warning = Color(0xFFE67E00);
  static const Color warningLight = Color(0xFFFFF1DC);
  static const Color danger = Color(0xFFC62828);
  static const Color dangerLight = Color(0xFFFDECEC);
  static const Color info = Color(0xFF0A7E82);
  static const Color infoLight = Color(0xFFE0F2F2);

  // Yüzeyler
  static const Color background = Colors.white;
  static const Color surface = Color(0xFFF7F7F8);
  static const Color surfaceMuted = Color(0xFFF0F0F2);
  static const Color border = Color(0xFFE5E5E8);
  static const Color borderStrong = Color(0xFFCFCFD3);

  // Metin
  static const Color textPrimary = Color(0xFF161616);
  static const Color textSecondary = Color(0xFF5A5A5A);
  static const Color textTertiary = Color(0xFF8A8A8A);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textOnBrand = Colors.white;
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

class AppRadius {
  const AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;
}

class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];
}

class AppDuration {
  const AppDuration._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
}

/// Uygulama tipografisi. Direkt `TextStyle(...)` yazmak yerine bunu kullan;
/// `Theme.of(context).textTheme` ile beraber tutarlı kalır.
class AppTextStyles {
  const AppTextStyles._();

  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.15,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: AppColors.brand,
    letterSpacing: 1.6,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.25,
  );

  static const TextStyle metric = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.1,
  );

  static const TextStyle metricLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static const TextStyle chip = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
}
