import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/accessibility/a11y.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/widgets/animated_entrance.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/pairing_models.dart';
import 'pairing_controller.dart';

/// مدیریت دسترسی‌ها.
///
/// ── چرا این صفحه هسته‌ی محصول است ───────────────────────────────────────
/// ادعای این محصول «ایمنی بدون از دست دادن استقلال» است. آن ادعا در این
/// صفحه اثبات می‌شود یا فرو می‌ریزد: کاربر باید هر لحظه بتواند ببیند چه
/// کسی چه چیزی از او می‌بیند، و بتواند در دو ضربه قطعش کند.
///
/// برای همین «قطع دسترسی» پشت هیچ منوی تودرتویی پنهان نشده و مستقیم روی
/// همان کارت است.
class GuardiansPage extends ConsumerStatefulWidget {
  const GuardiansPage({super.key});

  @override
  ConsumerState<GuardiansPage> createState() => _GuardiansPageState();
}

class _GuardiansPageState extends ConsumerState<GuardiansPage> {
  @override
  void initState() {
    super.initState();
    // پس از اولین فریم، تا تغییر وضعیت provider وسط ساخت درخت انجام نشود
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pairingControllerProvider.notifier).load();
    });
  }

  Future<void> _confirmRevoke(Guardianship link, {required bool iAmPrimary}) async {
    final String name = iAmPrimary
        ? (link.guardianUser?.fullName ?? 'این شخص')
        : (link.primaryUser?.fullName ?? 'این شخص');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('قطع دسترسی'),
          content: Text(
            iAmPrimary
                ? 'پس از قطع، $name دیگر موقعیت شما را نمی‌بیند و هشداری '
                    'دریافت نمی‌کند. هر زمان خواستید می‌توانید دوباره دعوتش کنید.'
                : 'پس از قطع، شما دیگر موقعیت $name را نمی‌بینید. برای اتصال '
                    'دوباره به کد دعوت تازه نیاز دارید.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('انصراف'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('قطع دسترسی'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final bool ok = await ref.read(pairingControllerProvider.notifier).revoke(link.id);

    if (!mounted) return;

    if (ok) {
      AppHaptics.success(ref);
      AppSnackBar.show(context, 'دسترسی قطع شد.', kind: AppSnackKind.success);
      A11y.announce(context, 'دسترسی $name قطع شد');
    }
  }

  Future<void> _editPermissions(Guardianship link) async {
    final Set<SharePermission> selected = link.permissions.toSet();

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'او چه چیزی ببیند؟',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final SharePermission permission in SharePermission.values)
                      SwitchListTile.adaptive(
                        value: selected.contains(permission),
                        onChanged: (bool value) {
                          setSheetState(() {
                            if (value) {
                              selected.add(permission);
                            } else {
                              selected.remove(permission);
                            }
                          });
                        },
                        title: Text(permission.label),
                        subtitle: Text(permission.description),
                        contentPadding: EdgeInsets.zero,
                      ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'ذخیره',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;

    final bool ok = await ref
        .read(pairingControllerProvider.notifier)
        .updatePermissions(link.id, selected.toList());

    if (!mounted) return;

    if (ok) {
      AppHaptics.success(ref);
      AppSnackBar.show(context, 'دسترسی‌ها به‌روزرسانی شد.', kind: AppSnackKind.success);
    }
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

    final List<Guardianship> guardians =
        state.lists.guardians.where((Guardianship g) => g.isActive).toList();
    final List<Guardianship> watching =
        state.lists.watching.where((Guardianship g) => g.isActive).toList();

    return AppScaffold(
      title: 'مراقبان و دسترسی‌ها',
      onRefresh: () => ref.read(pairingControllerProvider.notifier).load(),
      scrollable: true,
      body: Builder(
        builder: (BuildContext context) {
          if (state.loading && state.lists.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: AppSpacing.lg),
              child: LoadingSkeleton(lines: 3),
            );
          }

          if (state.lists.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyView(
                icon: Icons.group_outlined,
                title: 'هنوز به کسی وصل نیستید',
                message: 'می‌توانید کسی را دعوت کنید یا با کد دعوت به فردی وصل شوید.',
                actionLabel: 'دعوت از مراقب',
                onAction: () => context.push(AppRoutes.invite),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: AppSpacing.md),

              if (guardians.isNotEmpty) ...<Widget>[
                Text('این افراد شما را می‌بینند', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                for (int i = 0; i < guardians.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AnimatedEntrance(
                      index: i,
                      child: _PersonCard(
                        person: guardians[i].guardianUser,
                        permissions: guardians[i].permissions,
                        onEdit: () => _editPermissions(guardians[i]),
                        onRevoke: () =>
                            _confirmRevoke(guardians[i], iAmPrimary: true),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'دعوت از مراقب تازه',
                  icon: Icons.person_add_alt_rounded,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => context.push(AppRoutes.invite),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              if (watching.isNotEmpty) ...<Widget>[
                Text('شما همراه این افراد هستید', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                for (int i = 0; i < watching.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AnimatedEntrance(
                      index: i,
                      child: _PersonCard(
                        person: watching[i].primaryUser,
                        permissions: watching[i].permissions,
                        // مراقب اجازه‌ی تغییر سطح دسترسی خودش را ندارد؛
                        // این حق فقط برای کاربر اصلی است
                        onEdit: null,
                        onRevoke: () =>
                            _confirmRevoke(watching[i], iAmPrimary: false),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'اتصال به فرد تازه',
                  icon: Icons.qr_code_scanner_rounded,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => context.push(AppRoutes.redeem),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.permissions,
    required this.onEdit,
    required this.onRevoke,
  });

  final RelatedPerson? person;
  final List<SharePermission> permissions;
  final VoidCallback? onEdit;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = person?.fullName ?? 'بدون نام';
    final Color color = AppColors.parse(person?.avatarColor);

    return AppCard(
      semanticLabel: '$name. دسترسی‌ها: '
          '${permissions.map((SharePermission p) => p.label).join('، ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              A11y.decorative(
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color.withOpacity(0.15),
                  child: Text(
                    Fa.initials(name),
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name, style: theme.textTheme.titleMedium),
                    if (person?.phone != null)
                      Text(
                        Fa.digits(Fa.formatPhone(person!.phone!)),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              for (final SharePermission permission in permissions)
                Chip(
                  label: Text(permission.label),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),

          const Divider(height: AppSpacing.lg),

          Row(
            children: <Widget>[
              if (onEdit != null)
                Expanded(
                  child: AppButton(
                    label: 'تغییر دسترسی',
                    variant: AppButtonVariant.text,
                    onPressed: onEdit,
                  ),
                ),
              Expanded(
                child: AppButton(
                  label: 'قطع دسترسی',
                  variant: AppButtonVariant.text,
                  destructive: true,
                  onPressed: onRevoke,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
