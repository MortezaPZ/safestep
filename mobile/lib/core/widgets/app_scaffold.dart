import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// اسکلت مشترک صفحه‌ها.
///
/// سه کارِ تکراری را یک‌جا انجام می‌دهد تا در هیچ صفحه‌ای فراموش نشود:
///
/// ۱) حاشیه‌ی افقی یکسان برای همه‌ی صفحه‌ها
/// ۂ) `SafeArea` — بدون آن، محتوا زیر نوار وضعیت یا ناحیه‌ی ژست‌ها می‌رود
/// ۳) بستن صفحه‌کلید با لمس فضای خالی؛ در فرم‌های فارسی که صفحه‌کلید
///    نصف صفحه را می‌گیرد، نبودش آزاردهنده است
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.bottomBar,
    this.floatingActionButton,
    this.padded = true,
    this.showBackButton = true,
    this.scrollable = false,
    this.onRefresh,
    this.backgroundColor,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? bottomBar;
  final Widget? floatingActionButton;

  /// حاشیه‌ی افقی استاندارد. برای صفحه‌هایی که نقشه‌ی تمام‌صفحه دارند خاموش می‌شود.
  final bool padded;

  final bool showBackButton;

  /// محتوا را در یک اسکرول‌ویو می‌گذارد — برای فرم‌ها لازم است، وگرنه با
  /// باز شدن صفحه‌کلید یا بزرگ‌نمایی متن، خطای سرریز می‌دهد.
  final bool scrollable;

  /// اگر داده شود، «کشیدن برای تازه‌سازی» فعال می‌شود.
  final Future<void> Function()? onRefresh;

  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    Widget content = body;

    if (padded) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        child: content,
      );
    }

    if (scrollable) {
      content = SingleChildScrollView(
        // با کشیدن، صفحه‌کلید بسته شود — رفتار مورد انتظار در فرم‌های موبایل
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        child: content,
      );
    }

    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        child: content,
      );
    }

    return GestureDetector(
      // لمس فضای خالی، فوکوس را رها می‌کند و صفحه‌کلید بسته می‌شود
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: (title == null && titleWidget == null && actions == null)
            ? null
            : AppBar(
                title: titleWidget ?? (title == null ? null : Text(title!)),
                actions: actions,
                leading: leading,
                automaticallyImplyLeading: showBackButton,
              ),
        body: SafeArea(child: content),
        bottomNavigationBar: bottomBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}
