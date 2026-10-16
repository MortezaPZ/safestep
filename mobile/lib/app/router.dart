import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_home_page.dart';
import '../features/alerts/presentation/alerts_page.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/home/presentation/guardian_home_page.dart';
import '../features/home/presentation/supervisor_zones_page.dart';
import '../features/home/presentation/primary_home_page.dart';
import '../features/evaluation/presentation/evaluation_page.dart';
import '../features/fall/presentation/fall_check_page.dart';
import '../features/onboarding/presentation/role_select_page.dart';
import '../features/pairing/presentation/guardians_page.dart';
import '../features/pairing/presentation/invite_page.dart';
import '../features/pairing/presentation/redeem_page.dart';
import '../features/settings/presentation/accessibility_settings_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/splash/presentation/splash_page.dart';
import '../features/tracking/presentation/my_map_page.dart';
import '../features/watching/presentation/history_page.dart';
import '../features/watching/presentation/live_map_page.dart';

/// مسیرهای اپ.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/';
  static const String roleSelect = '/welcome';
  static const String login = '/login';
  static const String register = '/register';

  /// خانه‌ی کاربر اصلی (فرد تحت پایش)
  static const String home = '/home';
  static const String myMap = '/my-map';

  /// خانه‌ی مراقب
  static const String guardian = '/guardian';

  static const String settings = '/settings';
  static const String accessibility = '/settings/accessibility';
  static const String guardians = '/settings/guardians';

  static const String invite = '/pair/invite';
  static const String redeem = '/pair/redeem';

  static const String alerts = '/alerts';
  static const String fallCheck = '/fall-check';
  static const String evaluation = '/evaluation';

  /// نقشه‌ی زنده‌ی یک فرد تحت پایش
  static String mapFor(String userId) => '/watch/$userId';

  /// تاریخچه‌ی مسیر یک فرد
  static String historyFor(String userId) => '/watch/$userId/history';

  /// مسیرهایی که بدون ورود در دسترس‌اند.
  ///
  /// صفحه‌ی دسترس‌پذیری عمداً در این فهرست است: کسی که نمی‌تواند متن صفحه‌ی
  /// ورود را بخواند، باید بتواند پیش از هر کاری بزرگش کند.
  static const Set<String> publicRoutes = <String>{
    splash,
    roleSelect,
    login,
    register,
    accessibility,
  };

  /// خانه‌ی درست هر نقش.
  static const String admin = '/admin';
  static const String adminMap = '/admin/map';
  static const String adminAlerts = '/admin/alerts';
  static const String adminFamilies = '/admin/families';
  static const String adminFalls = '/admin/falls';
  static const String supervisorZones = '/supervisor/zones';

  static String homeFor(UserRole role) {
    if (role == UserRole.admin) return admin;
    if (role == UserRole.guardian) return guardian;
    return home;
  }
}

/// روتر اپ.
///
/// ── چرا هدایت در یک نقطه متمرکز است ─────────────────────────────────────
/// اگر هر صفحه خودش چک کند «آیا کاربر وارد شده؟»، اولین صفحه‌ای که یادمان
/// برود، یک نشت است: کسی با یک لینک عمیق (یا با نوتیفیکیشن در فاز دوم)
/// مستقیم واردش می‌شود. اینجا هیچ صفحه‌ای نمی‌تواند از این قاعده فرار کند.
///
/// ── و چرا حالت `unknown` جدی گرفته شده ──────────────────────────────────
/// تا وقتی توکن از Keychain خوانده نشده، نمی‌دانیم کاربر وارد هست یا نه.
/// در آن فاصله، همه روی صفحه‌ی آغازین می‌مانند. بدون این، کاربرِ واردشده
/// یک لحظه صفحه‌ی ورود را می‌بیند و بعد پرت می‌شود به خانه.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  // پلِ بین Riverpod و go_router: با هر تغییر وضعیت ورود، روتر دوباره
  // مسیر را ارزیابی می‌کند.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);

  ref.listen<AuthStatus>(
    authControllerProvider.select((AuthState state) => state.status),
    (AuthStatus? previous, AuthStatus next) => refresh.value++,
  );

  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,

    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authControllerProvider);
      final String location = state.matchedLocation;

      // هنوز نمی‌دانیم کاربر وارد هست یا نه
      if (auth.status == AuthStatus.unknown) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final bool isPublic = AppRoutes.publicRoutes.contains(location);

      if (!auth.isAuthenticated) {
        // صفحه‌ی آغازین برای کاربر واردنشده معنایی ندارد
        if (location == AppRoutes.splash) return AppRoutes.roleSelect;
        return isPublic ? null : AppRoutes.roleSelect;
      }

      // کاربر وارد شده و روی صفحه‌های ورود/ثبت‌نام است → به خانه‌ی نقشش
      final String home = AppRoutes.homeFor(auth.user!.role);

      if (location == AppRoutes.splash ||
          location == AppRoutes.roleSelect ||
          location == AppRoutes.login ||
          location == AppRoutes.register) {
        return home;
      }

      // خانه‌ی نقش دیگر هم قابل دسترسی نیست
      if (location == AppRoutes.home && auth.user!.role == UserRole.guardian) {
        return AppRoutes.guardian;
      }
      if (location == AppRoutes.home && auth.user!.role == UserRole.admin) {
        return AppRoutes.admin;
      }
      if (location == AppRoutes.guardian &&
          auth.user!.role != UserRole.guardian) {
        return AppRoutes.homeFor(auth.user!.role);
      }
      if (location.startsWith('/admin') && auth.user!.role != UserRole.admin) {
        return AppRoutes.homeFor(auth.user!.role);
      }
      if (location.startsWith('/supervisor') &&
          auth.user!.role != UserRole.guardian) {
        return AppRoutes.homeFor(auth.user!.role);
      }

      return null;
    },

    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.roleSelect,
        builder: (BuildContext context, GoRouterState state) =>
            const RoleSelectPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (BuildContext context, GoRouterState state) {
          final String role = state.uri.queryParameters['role'] ?? 'primary';
          return RegisterPage(initialRole: role);
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const PrimaryHomePage(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (BuildContext context, GoRouterState state) =>
            const AdminHomePage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'map',
            builder: (BuildContext context, GoRouterState state) =>
                const AdminSectionPage(section: AdminSection.map),
          ),
          GoRoute(
            path: 'alerts',
            builder: (BuildContext context, GoRouterState state) =>
                const AdminSectionPage(section: AdminSection.alerts),
          ),
          GoRoute(
            path: 'families',
            builder: (BuildContext context, GoRouterState state) =>
                const AdminSectionPage(section: AdminSection.families),
          ),
          GoRoute(
            path: 'falls',
            builder: (BuildContext context, GoRouterState state) =>
                const AdminSectionPage(section: AdminSection.falls),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.supervisorZones,
        builder: (BuildContext context, GoRouterState state) =>
            const SupervisorZonesPage(),
      ),
      GoRoute(
        path: AppRoutes.myMap,
        builder: (BuildContext context, GoRouterState state) =>
            const MyMapPage(),
      ),
      GoRoute(
        path: AppRoutes.guardian,
        builder: (BuildContext context, GoRouterState state) =>
            const GuardianHomePage(),
      ),
      GoRoute(
        path: AppRoutes.invite,
        builder: (BuildContext context, GoRouterState state) =>
            const InvitePage(),
      ),
      GoRoute(
        path: AppRoutes.redeem,
        builder: (BuildContext context, GoRouterState state) =>
            const RedeemPage(),
      ),
      GoRoute(
        path: AppRoutes.alerts,
        builder: (BuildContext context, GoRouterState state) =>
            AlertsListPage(alertId: state.uri.queryParameters['alertId']),
      ),
      GoRoute(
        path: AppRoutes.fallCheck,
        builder: (BuildContext context, GoRouterState state) => FallCheckPage(
          fallEventId: state.uri.queryParameters['id'] ?? '',
          countdownSec:
              int.tryParse(state.uri.queryParameters['sec'] ?? '') ?? 30,
        ),
      ),
      GoRoute(
        path: AppRoutes.evaluation,
        builder: (BuildContext context, GoRouterState state) =>
            const EvaluationPage(),
      ),
      GoRoute(
        path: '/watch/:userId',
        builder: (BuildContext context, GoRouterState state) {
          return LiveMapPage(userId: state.pathParameters['userId'] ?? '');
        },
        routes: <RouteBase>[
          GoRoute(
            path: 'history',
            builder: (BuildContext context, GoRouterState state) {
              return HistoryPage(
                userId: state.pathParameters['userId'] ?? '',
                // نام از پارامتر اختیاری می‌آید تا عنوان صفحه پیش از
                // بارگذاری داده هم درست باشد
                personName: state.uri.queryParameters['name'],
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'accessibility',
            builder: (BuildContext context, GoRouterState state) =>
                const AccessibilitySettingsPage(),
          ),
          GoRoute(
            path: 'guardians',
            builder: (BuildContext context, GoRouterState state) =>
                const GuardiansPage(),
          ),
        ],
      ),
    ],

    errorBuilder: (BuildContext context, GoRouterState state) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.explore_off_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'این صفحه پیدا نشد.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.splash),
                  child: const Text('بازگشت به خانه'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
});
