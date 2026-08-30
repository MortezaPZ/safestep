import 'package:flutter/material.dart';

import '../accessibility/a11y.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/app_exception.dart';
import 'app_button.dart';

/// چهار حالتی که هر صفحه‌ی داده‌محور باید داشته باشد.
///
/// ── چرا اینجا و نه در هر صفحه ───────────────────────────────────────────
/// صفحه‌ای که فقط حالت «موفق» دارد، در عمل سه حالتِ دیگرش را هم دارد —
/// فقط بدون طراحی: صفحه‌ی سفیدِ بی‌توضیح، چرخنده‌ی بی‌پایان، یا خطای خام.
/// این ویجت‌ها آن سه حالت را به رفتار پیش‌فرضِ درست تبدیل می‌کنند.

/// اسکلت بارگذاری.
///
/// به‌جای چرخنده استفاده می‌شود چون شکل نهایی محتوا را از قبل نشان می‌دهد و
/// جابه‌جایی ناگهانی چیدمان هنگام رسیدن داده را حذف می‌کند.
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    this.lines = 3,
    this.height = 92,
    this.semanticLabel = 'در حال بارگذاری',
  });

  final int lines;
  final double height;
  final String semanticLabel;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // اگر کاربر «کاهش حرکت» را روشن کرده، تپش اسکلت اجرا نمی‌شود
    if (AppMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSurface surface = AppSurface.of(context);

    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          children: List<Widget>.generate(widget.lines, (int index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return Opacity(
                    opacity: 0.45 + (_controller.value * 0.35),
                    child: child,
                  );
                },
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: surface.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// حالت خالی — وقتی داده‌ای نیست ولی خطایی هم رخ نداده.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSurface surface = AppSurface.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            A11y.decorative(
              Icon(icon, size: 56, color: surface.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: AppButtonVariant.outlined,
                fullWidth: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// حالت خطا.
///
/// دکمه‌ی «تلاش دوباره» فقط وقتی نشان داده می‌شود که تلاش دوباره واقعاً
/// منطقی باشد. نمایش این دکمه برای خطای «رمز نادرست» کاربر را در حلقه‌ی
/// بی‌فایده می‌اندازد.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
  });

  final AppException error;
  final VoidCallback? onRetry;

  IconData get _icon {
    switch (error.kind) {
      case AppErrorKind.network:
        return Icons.wifi_off_rounded;
      case AppErrorKind.permission:
        return Icons.lock_outline_rounded;
      case AppErrorKind.auth:
        return Icons.person_off_outlined;
      default:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool showRetry = onRetry != null && error.retryable;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              A11y.decorative(
                Icon(_icon, size: 56, color: theme.colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                error.message,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (showRetry) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'تلاش دوباره',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                  variant: AppButtonVariant.outlined,
                  fullWidth: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
