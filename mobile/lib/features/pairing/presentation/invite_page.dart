import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../domain/pairing_models.dart';
import 'pairing_controller.dart';

/// قالب داده‌ی QR.
///
/// یک URI با طرح اختصاصی، نه فقط شش رقم خام. دلیلش این است که اسکنر
/// عمومیِ گوشی هم بتواند تشخیص دهد این کد مربوط به کدام اپ است. اسکنر خودِ
/// ما هر دو قالب را می‌پذیرد.
String buildPairingUri(String code) => 'safestep://pair?code=$code';

/// استخراج کد از محتوای QR — هم URI و هم شش رقم خام را می‌پذیرد.
String? extractPairingCode(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  final String normalized = Fa.toLatinDigits(raw.trim());

  final Uri? uri = Uri.tryParse(normalized);
  if (uri != null && uri.scheme == 'safestep') {
    final String? code = uri.queryParameters['code'];
    if (code != null && RegExp(r'^\d{6}$').hasMatch(code)) return code;
  }

  final String digits = normalized.replaceAll(RegExp(r'\D'), '');
  return digits.length == 6 ? digits : null;
}

/// صفحه‌ی ساخت کد دعوت — سمت کاربر اصلی.
///
/// ── تصمیم محوری این صفحه ────────────────────────────────────────────────
/// کاربر **پیش از ساختن کد** انتخاب می‌کند که چه چیزی به اشتراک بگذارد.
/// این عمدی است و برعکسِ الگوی رایج «اول وصل شو، بعد تنظیم کن»: در آن
/// الگو، دسترسی کامل پیش‌فرض می‌شود و کسی هرگز کمش نمی‌کند.
///
/// اینجا پیش‌فرض هم حداقلی است: دیدن موقعیت و دریافت هشدار روشن، ولی
/// «دسترسی اضطراری» خاموش — کاربر باید آگاهانه روشنش کند.
class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key});

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  final Set<SharePermission> _selected = <SharePermission>{
    SharePermission.viewLocation,
    SharePermission.receiveAlerts,
  };

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // شمارش معکوس اعتبار کد، هر ثانیه یک بار
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(pairingControllerProvider).activeInvite != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final InviteCode? invite = await ref
        .read(pairingControllerProvider.notifier)
        .createInvite(_selected.toList());

    if (!mounted) return;

    if (invite?.code != null) {
      AppHaptics.success(ref);
      A11y.announce(context, 'کد دعوت ساخته شد: ${_spelled(invite!.code!)}');
    } else {
      final Object? error = ref.read(pairingControllerProvider).error;
      if (error != null) AppHaptics.error(ref);
    }
  }

  /// خواندن رقم‌به‌رقم برای صفحه‌خوان.
  ///
  /// اگر «۴۸۲۹۱۷» را یک‌جا به صفحه‌خوان بدهیم، آن را «چهارصد و هشتاد و دو
  /// هزار و نهصد و هفده» می‌خواند — که کاربر نمی‌تواند از رویش کد را
  /// بنویسد. جدا کردن ارقام با فاصله، این را حل می‌کند.
  static String _spelled(String code) =>
      Fa.digits(code.split('').join(' '));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PairingState state = ref.watch(pairingControllerProvider);
    final InviteCode? invite = state.activeInvite;

    ref.listen<PairingState>(pairingControllerProvider, (PairingState? _, PairingState next) {
      final String? message = next.error?.message;
      if (message != null) {
        AppSnackBar.show(context, message, kind: AppSnackKind.error);
        ref.read(pairingControllerProvider.notifier).clearError();
      }
    });

    return AppScaffold(
      title: 'دعوت از مراقب',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          if (invite?.code == null) ...<Widget>[
            AnimatedEntrance(
              index: 0,
              child: Text(
                'او چه چیزی را ببیند؟',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            AnimatedEntrance(
              index: 1,
              child: Text(
                'هر کدام را که خواستید روشن کنید. بعداً هم می‌توانید تغییرش دهید '
                'یا کلاً قطعش کنید.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            AnimatedEntrance(
              index: 2,
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < SharePermission.values.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      SwitchListTile.adaptive(
                        value: _selected.contains(SharePermission.values[i]),
                        onChanged: (bool value) {
                          AppHaptics.tap(ref);
                          setState(() {
                            if (value) {
                              _selected.add(SharePermission.values[i]);
                            } else {
                              _selected.remove(SharePermission.values[i]);
                            }
                          });
                        },
                        title: Text(SharePermission.values[i].label),
                        subtitle: Text(SharePermission.values[i].description),
                        isThreeLine: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xxs,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            AnimatedEntrance(
              index: 3,
              child: AppButton(
                label: 'ساخت کد دعوت',
                icon: Icons.qr_code_2_rounded,
                loading: state.busy,
                onPressed: _selected.isEmpty ? null : _create,
              ),
            ),

            if (_selected.isEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'حداقل یک مورد را روشن کنید.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ] else
            _InviteCodeCard(
              invite: invite!,
              onDone: () {
                ref.read(pairingControllerProvider.notifier).dismissInvite();
              },
            ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// کارت نمایش کد ساخته‌شده.
class _InviteCodeCard extends ConsumerWidget {
  const _InviteCodeCard({required this.invite, required this.onDone});

  final InviteCode invite;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String code = invite.code ?? '';
    final Duration remaining = invite.remaining;
    final bool expired = remaining == Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: <Widget>[
              Text(
                'این کد را به مراقبتان بدهید',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── کد شش‌رقمی ───────────────────────────────────────────
              Semantics(
                label: 'کد دعوت',
                // رقم‌به‌رقم، تا صفحه‌خوان آن را عدد بزرگ نخواند
                value: Fa.digits(code.split('').join(' ')),
                child: ExcludeSemantics(
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    // ارقام لاتین، چون کاربر باید همین را تایپ کند
                    textDirection: TextDirection.ltr,
                    style: AppTypography.mono.copyWith(
                      color: expired
                          ? theme.disabledColor
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // ── QR ───────────────────────────────────────────────────
              if (!expired)
                A11y.decorative(
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      // QR باید همیشه روی سفید باشد، حتی در تم تیره؛
                      // وگرنه دوربین بعضی گوشی‌ها نمی‌خواندش
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: QrImageView(
                      data: buildPairingUri(code),
                      version: QrVersions.auto,
                      size: 190,
                      backgroundColor: Colors.white,
                      // تصحیح خطای متوسط: اگر گوشه‌ی تصویر کمی محو باشد
                      // (عکس گرفتن از صفحه‌ی گوشی دیگر) باز هم خوانده می‌شود
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.md),

              // ── شمارش معکوس ──────────────────────────────────────────
              Semantics(
                liveRegion: true,
                child: Text(
                  expired
                      ? 'این کد منقضی شده است.'
                      : 'اعتبار تا ${Fa.duration(remaining)} دیگر',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: expired ? theme.colorScheme.error : null,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: AppSpacing.xs),

              Text(
                'کد فقط یک بار قابل استفاده است و پس از بستن این صفحه دیگر '
                'نمایش داده نمی‌شود.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                label: 'کپی کد',
                icon: Icons.copy_rounded,
                variant: AppButtonVariant.outlined,
                onPressed: expired
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (!context.mounted) return;
                        AppSnackBar.show(
                          context,
                          'کد در حافظه کپی شد.',
                          kind: AppSnackKind.success,
                        );
                      },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'تمام شد',
                onPressed: onDone,
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.md),

        // یادآوری صریح: کاربر باید بداند چه چیزی را به اشتراک گذاشته
        AppCard(
          accentColor: AppColors.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('با این کد، او می‌تواند:', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              for (final SharePermission permission in invite.permissions)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      A11y.decorative(
                        const Icon(Icons.check_rounded, size: 18),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          permission.description,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
