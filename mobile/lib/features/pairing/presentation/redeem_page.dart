import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/main_nav.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../domain/pairing_models.dart';
import 'invite_page.dart' show extractPairingCode;
import 'pairing_controller.dart';

/// وارد کردن کد دعوت — سمت مراقب.
///
/// ── چرا دو راه، و چرا تایپ دستی اولین راه است ───────────────────────────
/// اسکن QR سریع‌تر است، اما فرض می‌گیرد دو نفر کنار هم‌اند. در عمل، کاربر
/// اصلی کد را با پیامک یا تلفن می‌فرستد. مهم‌تر از آن: کاربر نابینا
/// نمی‌تواند دوربین را روی QR تنظیم کند.
///
/// پس ورودی متنی، راهِ اصلی است و اسکنر، میان‌بُر.
class RedeemPage extends ConsumerStatefulWidget {
  const RedeemPage({super.key});

  @override
  ConsumerState<RedeemPage> createState() => _RedeemPageState();
}

class _RedeemPageState extends ConsumerState<RedeemPage> {
  final TextEditingController _code = TextEditingController();
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit([String? scanned]) async {
    final String raw = scanned ?? _code.text;
    final String digits = Fa.toLatinDigits(raw).replaceAll(RegExp(r'\D'), '');

    if (digits.length != 6) {
      setState(() => _codeError = 'کد دعوت باید ۶ رقم باشد.');
      AppHaptics.error(ref);
      return;
    }

    setState(() => _codeError = null);

    final Guardianship? result =
        await ref.read(pairingControllerProvider.notifier).redeem(digits);

    if (!mounted) return;

    if (result != null) {
      AppHaptics.success(ref);
      final String name = result.primaryUser?.fullName ?? 'کاربر';
      A11y.announceAssertive(context, 'اتصال برقرار شد. شما اکنون همراه $name هستید.');
      AppSnackBar.show(
        context,
        'اتصال برقرار شد. شما اکنون همراه $name هستید.',
        kind: AppSnackKind.success,
      );
      Navigator.of(context).pop(true);
    } else {
      AppHaptics.error(ref);
    }
  }

  Future<void> _openScanner() async {
    final String? scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _ScannerPage()),
    );

    if (scanned == null || !mounted) return;

    _code.text = scanned;
    await _submit(scanned);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PairingState state = ref.watch(pairingControllerProvider);

    ref.listen<PairingState>(pairingControllerProvider, (PairingState? _, PairingState next) {
      final String? message = next.error?.message;
      if (message != null) {
        AppSnackBar.show(context, message, kind: AppSnackKind.error);
        ref.read(pairingControllerProvider.notifier).clearError();
      }
    });

    return AppScaffold(
      title: 'اتصال به فرد تحت پایش',
      showBackButton: false,
      bottomBar: const MainNav(current: 'family'),
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          AnimatedEntrance(
            index: 0,
            child: Text(
              'کد شش‌رقمی‌ای که برایتان فرستاده شده را وارد کنید.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedEntrance(
            index: 1,
            child: Text(
              'این کد فقط ۱۵ دقیقه اعتبار دارد و یک بار قابل استفاده است.',
              style: theme.textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          AnimatedEntrance(
            index: 2,
            child: AppTextField(
              controller: _code,
              label: 'کد دعوت',
              hint: '123456',
              latinDigits: true,
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.pin_rounded,
              errorText: _codeError,
              onSubmitted: (_) => _submit(),
              semanticLabel: 'کد دعوت، شش رقم',
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          AnimatedEntrance(
            index: 3,
            child: AppButton(
              label: 'اتصال',
              loading: state.busy,
              onPressed: () => _submit(),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          AnimatedEntrance(
            index: 4,
            child: AppButton(
              label: 'اسکن کد QR',
              icon: Icons.qr_code_scanner_rounded,
              variant: AppButtonVariant.outlined,
              onPressed: _openScanner,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          AnimatedEntrance(
            index: 5,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('کد را از کجا بیاورم؟', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'فردی که می‌خواهید همراهش باشید، باید در اپ خودش وارد بخش '
                    '«دعوت از مراقب» شود و کد بسازد. او تعیین می‌کند شما چه چیزی '
                    'را ببینید.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/* ═══════════════════════════ اسکنر ═══════════════════════════ */

/// صفحه‌ی اسکن QR.
///
/// دوربین با خروج از صفحه بسته می‌شود — نه فقط برای مصرف باتری: دوربینِ باز
/// در یک اپ ردیابی، دقیقاً همان چیزی است که کاربر نگرانش است.
class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  /// جلوگیری از پردازش چندباره‌ی یک اسکن؛ دوربین ممکن است یک کد را در
  /// چند فریم پشت سر هم تشخیص دهد.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final Barcode barcode in capture.barcodes) {
      final String? code = extractPairingCode(barcode.rawValue);
      if (code != null) {
        _handled = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسکن کد دعوت')),
      body: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // اگر مجوز دوربین رد شود یا دوربین در دسترس نباشد، به‌جای صفحه‌ی
            // سیاه، پیام روشن و راه جایگزین نشان داده می‌شود
            errorBuilder: (BuildContext context, MobileScannerException error, Widget? child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.no_photography_outlined, size: 56),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'دسترسی به دوربین ممکن نشد. می‌توانید کد را دستی وارد کنید.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'بازگشت',
                        fullWidth: false,
                        variant: AppButtonVariant.outlined,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // کادر راهنمای اسکن
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
          ),

          Positioned(
            bottom: AppSpacing.xxl,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Text(
                'کد QR را داخل کادر بگیرید',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
