import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// ورود نرم عناصر به صفحه: محو‌شدن به‌همراه لغزش کوتاه به بالا.
///
/// ── چرا لغزش «به بالا» و نه از کنار ─────────────────────────────────────
/// در رابط راست‌به‌چپ، لغزش افقی باید جهتش برعکس شود وگرنه حس «برگشت»
/// می‌دهد. حرکت عمودی این مشکل را ندارد و در هر دو جهت یکسان خوانده
/// می‌شود — یک تصمیم کوچک که کل اپ را از یک دسته باگ RTL نجات می‌دهد.
///
/// ── و چرا فاصله‌ی زمانی پلکانی ──────────────────────────────────────────
/// وقتی چند کارت با تأخیر کوتاهِ پشت سر هم ظاهر می‌شوند، چشم ترتیب را
/// دنبال می‌کند و صفحه «ساخته شدن» را نشان می‌دهد نه «پریدن». سقف تأخیر
/// عمداً کم است: کاربری که صفحه را می‌شناسد نباید منتظر انیمیشن بماند.
class AnimatedEntrance extends StatefulWidget {
  const AnimatedEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offsetY = 14,
  });

  final Widget child;

  /// جایگاه عنصر در فهرست — تأخیر ورود از روی همین محاسبه می‌شود.
  final int index;

  final double offsetY;

  @override
  State<AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.normal,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // انیمیشن ورود دیگر محتوا را پنهان نمی‌کند. روی گوشی، تیکرِ گذار صفحه
    // گاهی تمام نمی‌شد و کارت‌ها روی شفافیت صفر می‌ماندند.
    _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.enter,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
