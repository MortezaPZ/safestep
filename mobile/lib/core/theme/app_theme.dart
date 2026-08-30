import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// ساخت تم روشن، تیره و نسخه‌های کنتراست بالا.
///
/// چهار ترکیب ممکن است (روشن/تیره × عادی/کنتراست بالا) و همه از یک تابع
/// ساخته می‌شوند. اگر برای هر کدام تم جدا می‌نوشتیم، اولین تغییر طراحی در
/// یکی از آن‌ها فراموش می‌شد و اپ ناهماهنگ می‌گشت.
class AppTheme {
  const AppTheme._();

  static ThemeData light({bool highContrast = false}) => _build(
        brightness: Brightness.light,
        highContrast: highContrast,
      );

  static ThemeData dark({bool highContrast = false}) => _build(
        brightness: Brightness.dark,
        highContrast: highContrast,
      );

  static ThemeData _build({
    required Brightness brightness,
    required bool highContrast,
  }) {
    final bool isDark = brightness == Brightness.dark;

    final Color primary = highContrast
        ? (isDark ? AppColors.hcDarkPrimary : AppColors.hcLightPrimary)
        : AppColors.primary;

    final Color background = highContrast
        ? (isDark ? AppColors.hcDarkBackground : AppColors.hcLightBackground)
        : (isDark ? AppColors.darkBackground : AppColors.lightBackground);

    final Color surface = highContrast
        ? (isDark ? AppColors.hcDarkSurface : AppColors.hcLightSurface)
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final Color border = highContrast
        ? (isDark ? AppColors.hcDarkBorder : AppColors.hcLightBorder)
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    final Color textPrimary = highContrast
        ? (isDark ? AppColors.hcDarkText : AppColors.hcLightText)
        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary);

    // در کنتراست بالا، متن ثانویه هم به رنگ متن اصلی می‌رسد: خاکستریِ ملایم
    // دقیقاً همان چیزی است که کاربر کم‌بینا نمی‌بیند.
    final Color textSecondary = highContrast
        ? textPrimary
        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);

    final Color onPrimary = isDark && highContrast ? Colors.black : Colors.white;

    // مرزها در حالت کنتراست بالا ضخیم‌تر می‌شوند تا شکل عناصر بدون تکیه بر
    // اختلاف رنگِ ظریف هم قابل تشخیص باشد.
    final double borderWidth = highContrast ? 2 : 1;

    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      error: AppColors.formError,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    final TextTheme textTheme = AppTypography.textTheme(
      primary: textPrimary,
      secondary: textSecondary,
    );

    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(color: border, width: borderWidth),
    );

    // نکته: `cardTheme` و `dialogTheme` عمداً اینجا تنظیم نمی‌شوند. نوعِ
    // این دو فیلد در نسخه‌های اخیر Flutter از `CardTheme` به `CardThemeData`
    // تغییر کرده و مقداردهی‌شان، پروژه را به یک بازه‌ی نسخه‌ی خاص گره می‌زند.
    // به‌جایش، کارت‌ها و دیالوگ‌ها از ویجت‌های خودمان (`AppCard`) استایل
    // می‌گیرند که همین رنگ و شعاع و ضخامت مرز را از `AppSurface` می‌خوانند.
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,

      // گذار پیش‌فرض صفحه‌ها روی هر دو سکو یکسان باشد تا رفتار اپ قابل
      // پیش‌بینی بماند — کاربری که با TalkBack کار می‌کند، به ترتیب ثابت
      // اتفاق‌ها تکیه می‌کند.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: highContrast ? 0 : 1,
        centerTitle: true,
        foregroundColor: textPrimary,
        titleTextStyle: textTheme.titleLarge,
      ),

      dividerTheme: DividerThemeData(
        color: border,
        thickness: borderWidth,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
          textStyle: textTheme.labelLarge?.copyWith(color: onPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          animationDuration: AppMotion.fast,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
          textStyle: textTheme.labelLarge?.copyWith(color: primary),
          side: BorderSide(color: primary, width: borderWidth + 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          // حتی دکمه‌ی متنی هم باید هدف لمسی کامل داشته باشد
          minimumSize: const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          textStyle: textTheme.labelLarge?.copyWith(color: primary),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: highContrast
            ? surface
            : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: primary, width: borderWidth + 1),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.formError, width: borderWidth + 1),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: AppColors.formError, width: borderWidth + 1),
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: highContrast ? textSecondary : AppColors.lightTextMuted,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.formError),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : const Color(0xFF232A35),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: textTheme.labelMedium?.copyWith(color: primary),
        unselectedLabelStyle: textTheme.labelMedium,
        type: BottomNavigationBarType.fixed,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: border, width: borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),

      listTileTheme: ListTileThemeData(
        minVerticalPadding: AppSpacing.sm,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
        iconColor: textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
    );
  }
}

/// دسترسی ویجت‌ها به مقادیری که در `ColorScheme` جا نمی‌شوند.
///
/// رنگ مرز و ضخامتش، و اینکه حالت کنتراست بالا فعال است یا نه، اطلاعاتی
/// است که ویجت‌های سفارشی لازم دارند ولی `ThemeData` جای استانداردی
/// برایشان ندارد. به‌جای پاس دادن دستی در همه‌ی سازنده‌ها، از همین جا
/// خوانده می‌شود.
class AppSurface {
  const AppSurface({
    required this.border,
    required this.borderWidth,
    required this.highContrast,
    required this.surfaceAlt,
    required this.textMuted,
  });

  final Color border;
  final double borderWidth;
  final bool highContrast;
  final Color surfaceAlt;
  final Color textMuted;

  /// ساخت از روی تم جاری. هیچ ویجتی نباید رنگ مرز را خودش حدس بزند.
  static AppSurface of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color border = theme.dividerTheme.color ?? AppColors.lightBorder;
    final double width = theme.dividerTheme.thickness ?? 1;

    return AppSurface(
      border: border,
      borderWidth: width,
      highContrast: width >= 2,
      surfaceAlt: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
      textMuted: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
    );
  }
}
