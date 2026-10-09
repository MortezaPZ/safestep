import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../tracking/presentation/zone_overlay.dart';
import '../../watching/domain/watched_person.dart';
import '../../watching/presentation/watching_controller.dart';

/// تعریف محدوده امن، فقط برای ناظر اصلی.
class SupervisorZonesPage extends ConsumerStatefulWidget {
  const SupervisorZonesPage({super.key});

  @override
  ConsumerState<SupervisorZonesPage> createState() => _SupervisorZonesPageState();
}

class _SupervisorZonesPageState extends ConsumerState<SupervisorZonesPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _radius = TextEditingController(text: '150');
  String? _subjectId;
  List<MapZone> _zones = const <MapZone>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(watchingControllerProvider.notifier).load();
      if (!mounted) return;
      final List<WatchedPerson> mains = _mains;
      if (mains.isNotEmpty) {
        setState(() => _subjectId = mains.first.userId);
        await _loadZones();
      }
    });
  }

  List<WatchedPerson> get _mains {
    return ref
        .read(watchingControllerProvider)
        .people
        .where((WatchedPerson person) => person.isMainSupervisor)
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _loadZones() async {
    final String? subjectId = _subjectId;
    if (subjectId == null) return;
    try {
      final Map<String, dynamic> data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
        ApiEndpoints.safeZones,
        (dynamic raw) => Map<String, dynamic>.from(raw as Map),
        query: <String, dynamic>{'subjectUserId': subjectId},
      );
      if (!mounted) return;
      setState(() => _zones = MapZone.parseList(data['zones']));
    } catch (_) {
      if (mounted) setState(() => _zones = const <MapZone>[]);
    }
  }

  Future<void> _create() async {
    final String? subjectId = _subjectId;
    final String name = _name.text.trim();
    final int? radius = int.tryParse(_radius.text.trim());
    if (subjectId == null || name.length < 2 || radius == null || radius < 50) {
      AppSnackBar.show(context, 'نام و شعاع حداقل ۵۰ متر را وارد کنید.');
      return;
    }
    WatchedPerson? person;
    for (final WatchedPerson item in _mains) {
      if (item.userId == subjectId) person = item;
    }
    final double lat = person?.location?.lat ?? 35.7219;
    final double lng = person?.location?.lng ?? 51.4056;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post<Map<String, dynamic>>(
        ApiEndpoints.safeZones,
        (dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
        body: <String, dynamic>{
          'name': name,
          'centerLat': lat,
          'centerLng': lng,
          'radiusM': radius,
          'subjectUserId': subjectId,
        },
      );
      _name.clear();
      if (mounted) {
        AppSnackBar.show(
          context,
          person?.location == null
              ? 'محدوده ثبت شد. چون موقعیت زنده نبود، مرکز روی تهران گذاشته شد.'
              : 'محدوده «$name» روی موقعیت فعلی کاربر اصلی ثبت شد.',
        );
      }
      await _loadZones();
      await ref.read(watchingControllerProvider.notifier).load();
    } catch (error) {
      if (mounted) AppSnackBar.show(context, 'ثبت محدوده نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<WatchedPerson> mains = ref.watch(watchingControllerProvider).people
        .where((WatchedPerson person) => person.isMainSupervisor)
        .toList();
    return AppScaffold(
      title: 'ابزار ناظر اصلی',
      body: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
        children: <Widget>[
          if (mains.isEmpty)
            const Text('فقط ناظر اصلی می‌تواند محدوده امن تعریف کند.')
          else ...<Widget>[
            DropdownButton<String>(
              isExpanded: true,
              value: _subjectId != null && mains.any((WatchedPerson p) => p.userId == _subjectId)
                  ? _subjectId
                  : mains.first.userId,
              items: <DropdownMenuItem<String>>[
                for (final WatchedPerson person in mains)
                  DropdownMenuItem<String>(
                    value: person.userId,
                    child: Text(person.person.fullName),
                  ),
              ],
              onChanged: (String? value) {
                setState(() => _subjectId = value);
                _loadZones();
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'نام محدوده، مثلاً خانه'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _radius,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'شعاع به متر'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: _busy ? 'در حال ثبت…' : 'ثبت محدوده امن',
              onPressed: _busy ? null : _create,
            ),
            const SizedBox(height: AppSpacing.lg),
            const _PrimaryDocumentsForm(),
            const SizedBox(height: AppSpacing.lg),
            Text('محدوده‌های فعلی', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (_zones.isEmpty)
              const Text('هنوز محدوده‌ای نیست.')
            else
              for (final MapZone zone in _zones)
                AppCard(
                  child: Text('${zone.name} — شعاع ${zone.radiusM.round()} متر'),
                ),
          ],
        ],
      ),
    );
  }
}

class _PrimaryDocumentsForm extends ConsumerStatefulWidget {
  const _PrimaryDocumentsForm();

  @override
  ConsumerState<_PrimaryDocumentsForm> createState() => _PrimaryDocumentsFormState();
}

class _PrimaryDocumentsFormState extends ConsumerState<_PrimaryDocumentsForm> {
  final TextEditingController _condition = TextEditingController();
  String _status = '';
  bool _busy = false;

  @override
  void dispose() {
    _condition.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final List<WatchedPerson> mains = ref
        .read(watchingControllerProvider)
        .people
        .where((WatchedPerson person) => person.isMainSupervisor)
        .toList();
    if (mains.isEmpty) return;
    setState(() => _busy = true);
    try {
      final ByteData bytes = await rootBundle.load('assets/images/logo-hamghadam.jpg');
      final String imageUrl =
          'data:image/jpeg;base64,${base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
      final Map<String, dynamic> body = <String, dynamic>{
        'documentType': 'identity',
        'imageUrl': imageUrl,
        'subjectUserId': mains.first.userId,
      };
      final String condition = _condition.text.trim();
      if (condition.length >= 2) body['healthCondition'] = condition;
      await ref.read(apiClientProvider).post<Map<String, dynamic>>(
        '/documents',
        (dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
        body: body,
      );
      _condition.clear();
      if (mounted) {
        setState(() => _status = 'مدرک برای تأیید مدیر ارسال شد. مشکل کنار اسم، بعد از تأیید دیده می‌شود.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'ارسال مدرک نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('ارسال مدارک کاربر اصلی', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text('ناظر اصلی می‌تواند مدرک هویت کاربر اصلی را برای تأیید مدیر بفرستد.'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _condition,
            decoration: const InputDecoration(hintText: 'مشکل شخص، مثلاً مشکل قلب'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: _busy ? 'در حال ارسال…' : 'ارسال مدرک',
            onPressed: _busy ? null : _send,
          ),
          if (_status.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(_status),
          ],
        ],
      ),
    );
  }
}
