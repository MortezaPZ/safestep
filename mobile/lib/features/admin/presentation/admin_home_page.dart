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
  List<Map<String, dynamic>> _pending = const <Map<String, dynamic>>[];

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
        final List<Map<String, dynamic>> parsed = <Map<String, dynamic>>[];
        for (final dynamic item in docs) {
          if (item is Map) parsed.add(Map<String, dynamic>.from(item));
        }
        setState(() {
          _pending = _tab == 2 ? parsed : const <Map<String, dynamic>>[];
          _text = parsed.isEmpty
              ? 'مدرکی در این بخش نیست.'
              : parsed.map((Map<String, dynamic> map) {
                  final health = map['healthCondition'];
                  return '${map['userName'] ?? 'کاربر'} — ${map['status']}'
                      '${health == null ? '' : ' — مشکل: $health'}';
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

  Future<void> _approve(Map<String, dynamic> doc) async {
    final TextEditingController condition = TextEditingController(
      text: (doc['healthCondition'] ?? '').toString(),
    );
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('تأیید مدرک'),
        content: TextField(
          controller: condition,
          decoration: const InputDecoration(hintText: 'مشکل شخص، مثلاً مشکل قلب'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأیید')),
        ],
      ),
    );
    final String health = condition.text.trim();
    condition.dispose();
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).post<Map<String, dynamic>>(
        '/admin/documents/${doc['id']}/approve',
        (dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
        body: health.length >= 2 ? <String, dynamic>{'healthCondition': health} : <String, dynamic>{},
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _text = 'تأیید مدرک انجام نشد.');
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = <String>[
      'پشتیبانی',
      'کل مدارک',
      'در انتظار',
      'تأییدشده',
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
          Expanded(
            child: ListView(
              children: <Widget>[
                Text(_text),
                if (_tab == 2)
                  for (final Map<String, dynamic> doc in _pending)
                    ListTile(
                      title: Text('${doc['userName'] ?? 'کاربر'}'),
                      subtitle: const Text('بعد از تأیید، مشکل کنار اسم کاربر دیده می‌شود.'),
                      trailing: TextButton(
                        onPressed: () => _approve(doc),
                        child: const Text('تأیید'),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum AdminSection { map, alerts, families, falls }

/// صفحه‌های منوی مدیر: نقشه بدون مختصات، هشدار، خانواده و گزارش سقوط.
class AdminSectionPage extends ConsumerStatefulWidget {
  const AdminSectionPage({super.key, required this.section});

  final AdminSection section;

  @override
  ConsumerState<AdminSectionPage> createState() => _AdminSectionPageState();
}

class _AdminSectionPageState extends ConsumerState<AdminSectionPage> {
  List<Map<String, dynamic>> _rows = const <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ApiClient api = ref.read(apiClientProvider);
    try {
      final String path = switch (widget.section) {
        AdminSection.alerts => '/admin/alerts',
        AdminSection.falls => '/admin/falls',
        _ => '/admin/families',
      };
      final String key = switch (widget.section) {
        AdminSection.alerts => 'alerts',
        AdminSection.falls => 'falls',
        _ => 'families',
      };
      final Map<String, dynamic> data = await api.get<Map<String, dynamic>>(
        path,
        (dynamic raw) => Map<String, dynamic>.from(raw as Map),
      );
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
      for (final dynamic item in (data[key] as List?) ?? const <dynamic>[]) {
        if (item is Map) rows.add(Map<String, dynamic>.from(item));
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'بارگذاری نشد.';
      });
    }
  }

  String get _title {
    switch (widget.section) {
      case AdminSection.map:
        return 'نقشه خانواده‌ها';
      case AdminSection.alerts:
        return 'هشدارها';
      case AdminSection.families:
        return 'خانواده‌ها';
      case AdminSection.falls:
        return 'تشخیص سقوط';
    }
  }

  String get _nav {
    switch (widget.section) {
      case AdminSection.map:
        return 'map';
      case AdminSection.alerts:
        return 'alerts';
      case AdminSection.families:
        return 'family';
      case AdminSection.falls:
        return 'home';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _title,
      showBackButton: false,
      bottomBar: MainNav(current: _nav),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
                  children: <Widget>[
                    if (widget.section == AdminSection.map)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(
                          'مختصات زنده و مسیر برای مدیر نشان داده نمی‌شود. فقط وضعیت محدوده هر خانواده اینجاست.',
                        ),
                      ),
                    if (_rows.isEmpty)
                      Text(widget.section == AdminSection.falls
                          ? 'گزارش سقوطی نیست. وقتی کاربر اصلی روی تشخیص سقوط بزند، گزارش اینجا می‌آید.'
                          : 'موردی نیست.')
                    else
                      for (final Map<String, dynamic> row in _rows) _tile(row),
                  ],
                ),
    );
  }

  Widget _tile(Map<String, dynamic> row) {
    if (widget.section == AdminSection.alerts || widget.section == AdminSection.falls) {
      return ListTile(
        title: Text('${row['subjectName'] ?? 'کاربر'}'),
        subtitle: Text('${row['title'] ?? ''}'),
      );
    }
    final String name = '${row['primaryName'] ?? 'کاربر'}';
    final String? health = row['healthCondition'] as String?;
    final String zone = (row['zoneLabel'] as String?) ?? 'محدوده امن تعریف نشده';
    final List<dynamic> guardians = (row['guardians'] as List?) ?? const <dynamic>[];
    final String phones = guardians.map((dynamic item) {
      if (item is! Map) return '';
      return '${item['fullName'] ?? ''}';
    }).where((String value) => value.isNotEmpty).join('، ');
    return ListTile(
      title: Text(health == null || health.isEmpty ? name : '$name — مشکل: $health'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.section == AdminSection.map ? zone : 'مدرک: ${row['verificationStatus'] ?? ''}'),
          if (widget.section == AdminSection.families && phones.isNotEmpty) Text('ناظر: $phones'),
          if (widget.section == AdminSection.families && row['primaryPhone'] != null)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${row['primaryPhone']}', textAlign: TextAlign.left),
            ),
        ],
      ),
    );
  }
}
