import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../features/auth/domain/auth_models.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/watching/presentation/watching_controller.dart';
import 'app_snackbar.dart';

/// نوار پایین، هم‌تراز با تب‌های نسخهٔ وب.
class MainNav extends ConsumerWidget {
  const MainNav({super.key, required this.current});

  /// `home` | `map` | `alerts` | `family` | `settings`
  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(currentUserProvider)?.role;
    final bool guardian = role == UserRole.guardian;
    final bool admin = role == UserRole.admin;

    final List<_Item> items = <_Item>[
      _Item('home', 'خانه', Icons.home_outlined),
      _Item('map', 'نقشه', Icons.map_outlined),
      _Item('alerts', 'هشدارها', Icons.notifications_outlined),
      _Item('family', 'خانواده', Icons.people_outline),
      _Item('settings', 'تنظیمات', Icons.settings_outlined),
    ];

    return NavigationBar(
      selectedIndex: items.indexWhere((_Item item) => item.id == current).clamp(0, items.length - 1),
      onDestinationSelected: (int index) =>
          _go(context, ref, items[index].id, guardian, admin),
      destinations: <NavigationDestination>[
        for (final _Item item in items)
          NavigationDestination(icon: Icon(item.icon), label: item.label),
      ],
    );
  }

  void _go(BuildContext context, WidgetRef ref, String id, bool guardian, bool admin) {
    switch (id) {
      case 'home':
        context.go(admin
            ? AppRoutes.admin
            : guardian
                ? AppRoutes.guardian
                : AppRoutes.home);
      case 'map':
        if (admin) {
          context.go(AppRoutes.adminMap);
          return;
        }
        if (guardian) {
          final people = ref.read(watchingControllerProvider).people;
          if (people.isEmpty) {
            AppSnackBar.show(context, 'هنوز کسی برای نمایش روی نقشه وصل نشده.');
            return;
          }
          context.push(AppRoutes.mapFor(people.first.userId));
        } else {
          context.go(AppRoutes.myMap);
        }
      case 'alerts':
        context.go(admin ? AppRoutes.adminAlerts : AppRoutes.alerts);
      case 'family':
        if (admin) {
          context.go(AppRoutes.adminFamilies);
          return;
        }
        context.go(guardian ? AppRoutes.redeem : AppRoutes.guardians);
      case 'settings':
        context.go(AppRoutes.settings);
    }
  }
}

class _Item {
  const _Item(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}
