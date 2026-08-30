import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_spacing.dart';
import '../utils/fa.dart';

/// فیلد ورودی اپ.
///
/// ── نکته‌ی فارسی که همیشه فراموش می‌شود ─────────────────────────────────
/// صفحه‌کلید فارسیِ گوشی، ارقام فارسی (۰۹۱۲…) می‌فرستد. اگر همان را خام به
/// سرور بفرستیم، اعتبارسنجی شماره موبایل رد می‌شود و کاربر پیام «شماره
/// معتبر نیست» می‌بیند در حالی که شماره‌اش درست است. تبدیل ارقام باید
/// **حین تایپ** انجام شود، نه هنگام ارسال — تا کاربر همان چیزی را ببیند که
/// سرور می‌بیند.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.maxLength,
    this.autofocus = false,
    this.prefixIcon,
    this.suffix,
    this.latinDigits = false,
    this.semanticLabel,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final int? maxLength;
  final bool autofocus;
  final IconData? prefixIcon;
  final Widget? suffix;
  final FocusNode? focusNode;

  /// برای فیلدهای عددی: ارقام فارسی حین تایپ به لاتین تبدیل و متن
  /// چپ‌به‌راست نمایش داده می‌شود (شماره موبایل، کد دعوت).
  final bool latinDigits;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      label: semanticLabel ?? label,
      textField: true,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        maxLength: maxLength,
        style: theme.textTheme.bodyLarge,

        // فیلد عددی همیشه چپ‌به‌راست است، حتی در رابط راست‌به‌چپ:
        // شماره‌ی «۰۹۱۲۳۴۵۶۷۸۹» در جهت راست‌به‌چپ، برعکس خوانده می‌شود.
        textDirection: latinDigits ? TextDirection.ltr : null,
        textAlign: latinDigits ? TextAlign.left : TextAlign.start,

        inputFormatters: latinDigits
            ? <TextInputFormatter>[
                // تبدیل ارقام فارسی/عربی به لاتین، همان لحظه‌ی تایپ
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final String converted = Fa.toLatinDigits(newValue.text);
                  if (converted == newValue.text) return newValue;
                  return TextEditingValue(
                    text: converted,
                    selection: newValue.selection,
                    composing: TextRange.empty,
                  );
                }),
              ]
            : null,

        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          helperMaxLines: 3,
          errorText: errorText,
          errorMaxLines: 3,
          // شمارنده‌ی کاراکتر پیش‌فرض حذف می‌شود: با maxLength روی کد دعوت،
          // چیزی مثل «۶/۶» زیر فیلد ظاهر می‌شود که فقط شلوغی است
          counterText: '',
          // آیکون تزئینی است و معنایش در برچسب فیلد آمده؛ اگر از صفحه‌خوان
          // پنهان نشود، کاربر نابینا یک برچسب اضافی و بی‌معنا می‌شنود
          prefixIcon: prefixIcon == null
              ? null
              : ExcludeSemantics(
                  child: Icon(prefixIcon, size: 22, color: theme.colorScheme.onSurface),
                ),
          suffixIcon: suffix,
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        ),
      ),
    );
  }
}
