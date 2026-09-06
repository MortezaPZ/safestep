import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import 'package:safestep/l10n/app_localizations.dart';
import 'auth_controller.dart';

/// صفحه‌ی ورود.
///
/// ── مدیریت خطا ──────────────────────────────────────────────────────────
/// خطای اعتبارسنجیِ سرور اگر مربوط به یک فیلد مشخص باشد، زیر همان فیلد
/// می‌نشیند؛ بقیه‌ی خطاها به‌صورت پیام گذرا نمایش داده می‌شوند. نمایش
/// «شماره یا رمز نادرست است» زیر فیلد رمز، اطلاعات نادرست می‌دهد — سرور
/// عمداً نمی‌گوید کدامشان غلط بوده.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  String? _phoneError;
  String? _passwordError;
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// اعتبارسنجی سمت کلاینت.
  ///
  /// هدفش جایگزینی اعتبارسنجی سرور نیست — آن همیشه حرف آخر را می‌زند.
  /// هدفش این است که کاربر برای شنیدن «شماره‌ات ۱۰ رقم است» منتظر
  /// رفت‌وبرگشت شبکه نماند.
  bool _validate() {
    setState(() {
      _phoneError = Fa.isValidPhone(_phone.text)
          ? null
          : 'شماره موبایل را کامل و درست وارد کنید. نمونه: ۰۹۱۲۳۴۵۶۷۸۹';
      _passwordError =
          _password.text.isEmpty ? 'رمز عبور را وارد کنید.' : null;
    });
    return _phoneError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    // صفحه‌کلید بسته شود تا پیام خطا زیرش پنهان نماند
    FocusManager.instance.primaryFocus?.unfocus();

    final bool ok = await ref.read(authControllerProvider.notifier).login(
          phone: _phone.text,
          password: _password.text,
        );

    if (!mounted) return;

    if (ok) {
      AppHaptics.success(ref);
      A11y.announce(context, 'وارد شدید');
      // هدایت به خانه را روتر انجام می‌دهد؛ اینجا کاری لازم نیست
      return;
    }

    AppHaptics.error(ref);

    final AppException? error = ref.read(authControllerProvider).error;
    if (error == null) return;

    // خطای فیلدیِ سرور را زیر همان فیلد می‌گذاریم
    final Map<String, String>? fields = error.fieldErrors;
    if (fields != null && fields.isNotEmpty) {
      setState(() {
        _phoneError = fields['phone'] ?? _phoneError;
        _passwordError = fields['password'] ?? _passwordError;
      });
    } else {
      AppSnackBar.show(context, error.message, kind: AppSnackKind.error);
    }

    ref.read(authControllerProvider.notifier).clearError();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return AppScaffold(
      title: l10n.login,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),

          AnimatedEntrance(
            index: 0,
            child: Text(l10n.welcomeBack, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedEntrance(
            index: 1,
            child: Text(
              l10n.loginHint,
              style: theme.textTheme.bodyMedium,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          AnimatedEntrance(
            index: 2,
            child: AppTextField(
              controller: _phone,
              label: l10n.phoneLabel,
              hint: '09123456789',
              latinDigits: true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.phone_iphone_rounded,
              errorText: _phoneError,
              maxLength: 13,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              semanticLabel: 'شماره موبایل، یازده رقم',
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          AnimatedEntrance(
            index: 3,
            child: AppTextField(
              controller: _password,
              focusNode: _passwordFocus,
              label: l10n.passwordLabel,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.lock_outline_rounded,
              errorText: _passwordError,
              onSubmitted: (_) => _submit(),
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                tooltip: _obscure ? 'نمایش رمز' : 'پنهان کردن رمز',
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          AnimatedEntrance(
            index: 4,
            child: AppButton(
              label: l10n.login,
              loading: ref.watch(authControllerProvider).busy,
              onPressed: _submit,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          AnimatedEntrance(
            index: 5,
            child: AppButton(
              label: l10n.noAccount,
              variant: AppButtonVariant.text,
              onPressed: () => context.push(AppRoutes.roleSelect),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
