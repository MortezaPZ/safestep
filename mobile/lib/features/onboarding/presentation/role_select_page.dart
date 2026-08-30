import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/accessibility/a11y.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';

/// انتخاب نقش.
///
/// ── چرا اولین سؤال اپ، «شما کدامید» است ─────────────────────────────────
/// تجربه‌ی کاربر اصلی و مراقب کاملاً متفاوت است: یکی می‌خواهد امنیت داشته
/// باشد بدون آنکه احساس تحت‌نظر بودن کند، دیگری می‌خواهد خیالش راحت باشد.
/// پرسیدن این سؤال در ابتدا، اجازه می‌دهد از همان صفحه‌ی بعد، زبان و
/// چیدمان مناسب همان نقش را نشان دهیم.
///
/// این انتخاب قفل ابدی نیست: نقش واقعی در سرور از رابطه‌ی سرپرستی می‌آید و
/// یک نفر می‌تواند هم‌زمان کاربر اصلی و مراقبِ کسِ دیگری باشد.
class RoleSelectPage extends ConsumerWidget {
  const RoleSelectPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return AppScaffold(
      scrollable: true,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.push(AppRoutes.accessibility),
          icon: const Icon(Icons.text_fields_rounded),
          tooltip: 'اندازه‌ی متن و دسترس‌پذیری',
          // این دکمه عمداً در همین صفحه‌ی اول است: کاربری که نمی‌تواند متن
          // را بخواند، باید بتواند پیش از هر کار دیگری بزرگش کند.
          iconSize: 26,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          AnimatedEntrance(
            index: 0,
            child: Text('به ${AppConfig.appName} خوش آمدید',
                style: theme.textTheme.headlineMedium),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedEntrance(
            index: 1,
            child: Text(
              'برای شروع، مشخص کنید از کدام سمت وارد می‌شوید.',
              style: theme.textTheme.bodyLarge,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          AnimatedEntrance(
            index: 2,
            child: _RoleCard(
              icon: Icons.person_outline_rounded,
              color: AppColors.primary,
              title: 'خودم استفاده می‌کنم',
              description:
                  'موقعیتم را با کسانی که خودم انتخاب می‌کنم به اشتراک می‌گذارم '
                  'و در صورت نیاز، با یک دکمه کمک می‌خواهم.',
              onTap: () => context.push('${AppRoutes.register}?role=primary'),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          AnimatedEntrance(
            index: 3,
            child: _RoleCard(
              icon: Icons.favorite_outline_rounded,
              color: AppColors.success,
              title: 'مراقب یکی از عزیزانم هستم',
              description:
                  'با کد دعوتی که او برایم می‌فرستد وصل می‌شوم و در صورت نیاز '
                  'هشدار دریافت می‌کنم.',
              onTap: () => context.push('${AppRoutes.register}?role=guardian'),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          AnimatedEntrance(
            index: 4,
            child: AppButton(
              label: 'قبلاً حساب ساخته‌ام؛ وارد می‌شوم',
              variant: AppButtonVariant.text,
              onPressed: () => context.push(AppRoutes.login),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      // کل کارت یک گره‌ی معنایی است: کاربر صفحه‌خوان یک بار عنوان و توضیح را
      // می‌شنود و یک بار انتخاب می‌کند، نه اینکه سه بار انگشت بکشد.
      semanticLabel: '$title. $description',
      semanticHint: 'برای انتخاب، دو بار ضربه بزنید',
      child: Row(
        children: <Widget>[
          A11y.decorative(
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                // شفافیت کم روی رنگ اصلی، تا در هر دو تم قابل قبول بماند.
                // از `withOpacity` استفاده می‌شود و نه `withValues`، چون
                // دومی فقط در Flutter ۳٫۲۷ به بعد وجود دارد و پروژه را به
                // یک نسخه‌ی حداقلیِ بالاتر گره می‌زند.
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(description, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
