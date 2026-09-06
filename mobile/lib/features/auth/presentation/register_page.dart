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
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';
import 'auth_controller.dart';

/// صفحه‌ی ثبت‌نام.
///
/// نقش انتخاب‌شده در صفحه‌ی خوش‌آمد، از مسیر به اینجا می‌رسد و در بالای فرم
/// نمایش داده می‌شود — کاربر باید بتواند ببیند دارد چه چیزی می‌سازد و در
/// صورت اشتباه برگردد.
///
/// نقش در سمت سرور فقط «نقش پیش‌فرض حساب» است؛ دسترسی واقعی از رابطه‌ی
/// سرپرستی می‌آید. یعنی اگر کاربر اشتباه انتخاب کند، چیزی خراب نمی‌شود و
/// بعداً هم می‌تواند از سمت دیگر وصل شود.
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key, this.initialRole = 'primary'});

  /// `primary` یا `guardian` — هر مقدار دیگری به `primary` برمی‌گردد.
  final String initialRole;

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();

  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  String? _nameError;
  String? _phoneError;
  String? _passwordError;
  bool _obscure = true;
  final TextEditingController _otp = TextEditingController();
  bool _otpRequired = false;
  String? _otpHint;

  late final String _role =
      widget.initialRole == 'guardian' ? 'guardian' : 'primary';

  String get _roleLabel =>
      _role == 'guardian' ? 'مراقب' : 'کاربر اصلی';

  @override
  void initState() {
    super.initState();
    ref.read(authRepositoryProvider).publicConfig().then((Map<String, dynamic> cfg) {
      if (!mounted) return;
      setState(() {
        _otpRequired = cfg['phoneVerificationRequired'] == true;
        if (cfg['smsDriver'] == 'console') {
          _otpHint = 'کد در لاگ سرور چاپ شد (حالت توسعه)';
        }
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _otp.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _nameError = _name.text.trim().length < 2
          ? 'نام و نام خانوادگی را وارد کنید.'
          : null;
      _phoneError = Fa.isValidPhone(_phone.text)
          ? null
          : 'شماره موبایل را کامل و درست وارد کنید. نمونه: ۰۹۱۲۳۴۵۶۷۸۹';
      // همان حداقلی که سرور اعمال می‌کند؛ اگر این دو از هم جدا شوند، کاربر
      // فرم را پر می‌کند و تازه از سرور خطا می‌گیرد
      _passwordError = _password.text.length < 8
          ? 'رمز عبور باید حداقل ۸ کاراکتر باشد.'
          : null;
    });
    return _nameError == null && _phoneError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    FocusManager.instance.primaryFocus?.unfocus();

    String? token;
    if (_otpRequired) {
      final AuthRepository repo = ref.read(authRepositoryProvider);
      if (_otp.text.trim().isEmpty) {
        final String? hint = await repo.requestOtp(_phone.text, 'register');
        if (!mounted) return;
        AppSnackBar.show(context, hint ?? 'کد ارسال شد. آن را وارد کنید و دوباره بزنید.');
        return;
      }
      try {
        token = await repo.verifyOtp(_phone.text, _otp.text.trim(), 'register');
      } on AppException catch (error) {
        if (!mounted) return;
        AppSnackBar.show(context, error.message, kind: AppSnackKind.error);
        return;
      }
    }

    final bool ok = await ref.read(authControllerProvider.notifier).register(
          phone: _phone.text,
          password: _password.text,
          fullName: _name.text,
          role: _role == 'guardian' ? UserRole.guardian : UserRole.primary,
          verificationToken: token,
        );

    if (!mounted) return;

    if (ok) {
      AppHaptics.success(ref);
      A11y.announce(context, 'حساب شما ساخته شد');
      // روتر خودش به خانه‌ی نقش هدایت می‌کند
      return;
    }

    AppHaptics.error(ref);

    final AppException? error = ref.read(authControllerProvider).error;
    if (error == null) return;

    final Map<String, String>? fields = error.fieldErrors;
    if (fields != null && fields.isNotEmpty) {
      setState(() {
        _nameError = fields['fullName'] ?? _nameError;
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

    return AppScaffold(
      title: 'ثبت‌نام',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),

          AnimatedEntrance(
            index: 0,
            child: Semantics(
              label: 'نقش انتخاب‌شده: $_roleLabel',
              child: Row(
                children: <Widget>[
                  Chip(
                    avatar: Icon(
                      _role == 'guardian'
                          ? Icons.favorite_outline_rounded
                          : Icons.person_outline_rounded,
                      size: 18,
                    ),
                    label: Text(_roleLabel),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.roleSelect),
                    child: const Text('تغییر'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          AnimatedEntrance(
            index: 1,
            child: AppTextField(
              controller: _name,
              label: 'نام و نام خانوادگی',
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.badge_outlined,
              errorText: _nameError,
              onSubmitted: (_) => _phoneFocus.requestFocus(),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          AnimatedEntrance(
            index: 2,
            child: AppTextField(
              controller: _phone,
              focusNode: _phoneFocus,
              label: 'شماره موبایل',
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
              label: 'رمز عبور',
              helperText: 'حداقل ۸ کاراکتر',
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

          if (_otpRequired) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _otp,
              label: 'کد تأیید پیامک',
              helperText: _otpHint,
              keyboardType: TextInputType.number,
              latinDigits: true,
              prefixIcon: Icons.sms_outlined,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          AnimatedEntrance(
            index: 4,
            child: AppButton(
              label: 'ساخت حساب',
              loading: ref.watch(authControllerProvider).busy,
              onPressed: _submit,
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          AnimatedEntrance(
            index: 5,
            child: Text(
              'با ساخت حساب، شما تعیین می‌کنید چه کسی و تا چه حد موقعیت شما را '
              'ببیند. این تصمیم همیشه در دست خودتان است و هر زمان قابل تغییر.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
