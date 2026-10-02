import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/main_nav.dart';

/// پنل مدیر. مختصات و تاریخچهٔ مسیر اینجا نیست.
class AdminHomePage extends ConsumerStatefulWidget {
  const AdminHomePage({super.key});

  @override
  ConsumerState<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends ConsumerState<AdminHomePage> {
  int _tab = 0;
  String _text = 'در حال بارگذاری…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ApiClient api = ref.read(apiClientProvider);
    try {
      if (_tab == 0) {
        final data = await api.get<Map<String, dynamic>>(
          '/admin/support',
          (dynamic raw) => Map<String, dynamic>.from(raw as Map),
        );
        final threads = (data['threads'] as List?) ?? const [];
        setState(() {
          _text = threads.isEmpty
              ? 'پیام پشتیبانی نیست.'
              : threads.map((dynamic item) {
                  final map = Map<String, dynamic>.from(item as Map);
                  return '${map['fullName']} — ${map['messageCount']} پیام';
                }).join('\n');
        });
      } else if (_tab == 1 || _tab == 2 || _tab == 3) {
        final status = _tab == 1 ? 'all' : _tab == 2 ? 'pending' : 'approved';
        final data = await api.get<Map<String, dynamic>>(
          '/admin/documents',
          (dynamic raw) => Map<String, dynamic>.from(raw as Map),
          query: <String, dynamic>{'status': status},
        );
        final docs = (data['documents'] as List?) ?? const [];
        setState(() {
          _text = docs.isEmpty
              ? 'مدرکی در این بخش نیست.'
              : docs.map((dynamic item) {
                  final map = Map<String, dynamic>.from(item as Map);
                  final health = map['healthCondition'];
                  return '${map['userName'] ?? 'کاربر'} — ${map['status']}'
                      '${health == null ? '' : ' — $health'}';
                }).join('\n');
        });
      } else if (_tab == 4) {
        final data = await api.get<Map<String, dynamic>>(
          '/admin/families',
          (dynamic raw) => Map<String, dynamic>.from(raw as Map),
        );
        final families = (data['families'] as List?) ?? const [];
        setState(() {
          _text = families.map((dynamic item) {
            final map = Map<String, dynamic>.from(item as Map);
            return '${map['primaryName']} — مدرک: ${map['verificationStatus']}';
          }).join('\n');
        });
      } else if (_tab == 5) {
        final data = await api.get<Map<String, dynamic>>(
          '/admin/alerts',
          (dynamic raw) => Map<String, dynamic>.from(raw as Map),
        );
        final alerts = (data['alerts'] as List?) ?? const [];
        setState(() {
          _text = alerts.isEmpty
              ? 'هشداری نیست.'
              : alerts.map((dynamic item) {
                  final map = Map<String, dynamic>.from(item as Map);
                  return '${map['subjectName']}: ${map['title']}';
                }).join('\n');
        });
      } else {
        final data = await api.get<Map<String, dynamic>>(
          '/admin/falls',
          (dynamic raw) => Map<String, dynamic>.from(raw as Map),
        );
        final falls = (data['falls'] as List?) ?? const [];
        setState(() {
          _text = falls.isEmpty
              ? 'گزارش سقوطی نیست.'
              : falls.map((dynamic item) {
                  final map = Map<String, dynamic>.from(item as Map);
                  return '${map['subjectName']}: ${map['title']}';
                }).join('\n');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _text = 'بارگذاری نشد.');
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = <String>[
      'پشتیبانی',
      'کل مدارک',
      'در انتظار',
      'تأییدشده',
      'خانواده‌ها',
      'هشدارها',
      'تشخیص سقوط',
    ];
    return AppScaffold(
      title: 'مدیریت سامانه',
      showBackButton: false,
      bottomBar: const MainNav(current: 'home'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (int i = 0; i < labels.length; i++)
                ChoiceChip(
                  label: Text(labels[i]),
                  selected: _tab == i,
                  onSelected: (_) {
                    setState(() => _tab = i);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: SingleChildScrollView(child: Text(_text))),
        ],
      ),
    );
  }
}
