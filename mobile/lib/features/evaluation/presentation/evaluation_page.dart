import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fa.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../features/tracking/data/permission_service.dart';
import '../../../features/tracking/domain/location_sample.dart';
import '../data/evaluation_repository.dart';

class EvaluationPage extends ConsumerStatefulWidget {
  const EvaluationPage({super.key});

  @override
  ConsumerState<EvaluationPage> createState() => _EvaluationPageState();
}

class _EvaluationPageState extends ConsumerState<EvaluationPage> {
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();

  bool _loading = true;
  bool _capturing = false;
  bool _savingReference = false;
  bool _loadingSus = true;
  bool _submittingSus = false;
  String? _referenceError;
  String? _susError;
  String? _referenceMessage;
  String? _susMessage;
  List<String> _susItems = const <String>[];
  List<int> _choices = const <int>[1, 2, 3, 4, 5];
  final Map<int, int> _answers = <int, int>{};

  bool get _isPersian => Localizations.localeOf(context).languageCode == 'fa';
  EvaluationRepository get _repository =>
      ref.read(evaluationRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadReference();
    _loadSusForm();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadReference() async {
    setState(() {
      _loading = true;
      _referenceError = null;
    });
    try {
      final ReferencePoint? saved = await _repository.currentReference();
      if (!mounted) return;
      if (saved != null) {
        _latController.text = saved.lat.toStringAsFixed(6);
        _lngController.text = saved.lng.toStringAsFixed(6);
        _labelController.text = saved.label ?? '';
      }
    } catch (error) {
      if (mounted) _referenceError = _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSusForm() async {
    setState(() {
      _loadingSus = true;
      _susError = null;
    });
    try {
      final SusForm form = await _repository.susForm();
      if (!mounted) return;
      setState(() {
        _susItems = form.items;
        if (form.choices.isNotEmpty) _choices = form.choices;
      });
    } catch (error) {
      if (mounted) _susError = _message(error);
    } finally {
      if (mounted) setState(() => _loadingSus = false);
    }
  }

  Future<void> _fillFromGps() async {
    setState(() {
      _capturing = true;
      _referenceError = null;
      _referenceMessage = null;
    });
    try {
      final LocationPermissionService permissions = ref.read(
        locationPermissionServiceProvider,
      );
      final LocationPermissionState state =
          await permissions.requestForeground();
      if (!mounted) return;
      if (state == LocationPermissionState.serviceDisabled) {
        setState(
          () => _referenceError = _isPersian
              ? 'مکان گوشی خاموش است. ابتدا سرویس مکان را روشن کنید.'
              : 'Location is turned off. Turn it on and try again.',
        );
        return;
      }
      if (state == LocationPermissionState.permanentlyDenied) {
        setState(
          () => _referenceError = _isPersian
              ? 'مجوز مکان در تنظیمات گوشی بسته است.'
              : 'Location permission is blocked in system settings.',
        );
        return;
      }
      if (state != LocationPermissionState.granted &&
          state != LocationPermissionState.whileInUseOnly) {
        setState(
          () => _referenceError = _isPersian
              ? 'برای خواندن مختصات، مجوز مکان لازم است.'
              : 'Location permission is needed to read coordinates.',
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      _latController.text = position.latitude.toStringAsFixed(6);
      _lngController.text = position.longitude.toStringAsFixed(6);
      setState(
        () => _referenceMessage = _isPersian
            ? 'مختصات GPS تقریبی وارد شد. برای ارزیابی معتبر، آن را با مختصات نقطه‌ی مرجع اندازه‌گیری‌شده جایگزین کنید.'
            : 'Approximate GPS coordinates filled. Replace them with the surveyed reference coordinates for a valid evaluation.',
      );
    } catch (error) {
      if (mounted) setState(() => _referenceError = _message(error));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _saveReference() async {
    final double? lat = _parseCoordinate(_latController.text);
    final double? lng = _parseCoordinate(_lngController.text);
    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      setState(() {
        _referenceError = _isPersian
            ? 'عرض جغرافیایی باید بین ۹۰- تا ۹۰ و طول جغرافیایی بین ۱۸۰- تا ۱۸۰ باشد.'
            : 'Enter a valid latitude (−90 to 90) and longitude (−180 to 180).';
      });
      return;
    }
    setState(() {
      _savingReference = true;
      _referenceError = null;
      _referenceMessage = null;
    });
    try {
      await _repository.saveReference(
        lat: lat,
        lng: lng,
        label: _labelController.text,
      );
      if (!mounted) return;
      setState(
        () => _referenceMessage =
            _isPersian ? 'نقطه‌ی مرجع ذخیره شد.' : 'Reference point saved.',
      );
    } catch (error) {
      if (mounted) setState(() => _referenceError = _message(error));
    } finally {
      if (mounted) setState(() => _savingReference = false);
    }
  }

  Future<void> _submitSus() async {
    if (_answers.length != 10) return;
    setState(() {
      _submittingSus = true;
      _susError = null;
      _susMessage = null;
    });
    try {
      await _repository.submitSus(
        List<int>.generate(10, (int index) => _answers[index]!),
      );
      if (!mounted) return;
      setState(() {
        _answers.clear();
        _susMessage = _isPersian
            ? 'پاسخ شما ثبت شد. ممنون از وقتی که گذاشتید.'
            : 'Your responses were recorded. Thank you for your time.';
      });
    } catch (error) {
      if (mounted) setState(() => _susError = _message(error));
    } finally {
      if (mounted) setState(() => _submittingSus = false);
    }
  }

  double? _parseCoordinate(String input) {
    final String value = Fa.toLatinDigits(input.trim())
        .replaceAll('٫', '.')
        .replaceAll(',', '.');
    return double.tryParse(value);
  }

  String _message(Object error) {
    if (error is AppException) return error.message;
    return _isPersian
        ? 'ارتباط با سرور انجام نشد. دوباره تلاش کنید.'
        : 'Could not reach the server. Try again.';
  }

  List<String> _localizedSusItems() {
    if (_isPersian && _susItems.length == 10) return _susItems;
    if (!_isPersian) {
      return const <String>[
        'I think I would like to use this system often.',
        'I found the system unnecessarily complex.',
        'I thought the system was easy to use.',
        'I think I would need help from a technical person.',
        'I found the functions well integrated.',
        'I thought there was too much inconsistency.',
        'I imagine most people would learn to use it quickly.',
        'I found the system cumbersome.',
        'I felt confident using it.',
        'I needed to learn a lot before I could get going.',
      ];
    }
    return const <String>[
      'فکر می‌کنم دوست دارم اغلب از این سامانه استفاده کنم.',
      'این سامانه را بی‌جهت پیچیده یافتم.',
      'فکر می‌کنم استفاده از این سامانه آسان است.',
      'فکر می‌کنم برای استفاده از این سامانه به کمک یک فرد فنی نیاز دارم.',
      'کارکردهای مختلف این سامانه را به‌خوبی یکپارچه یافتم.',
      'در این سامانه ناسازگاری زیادی دیدم.',
      'تصور می‌کنم بیشتر افراد خیلی سریع کار با این سامانه را یاد می‌گیرند.',
      'استفاده از این سامانه را دست‌وپاگیر یافتم.',
      'با استفاده از این سامانه احساس اطمینان داشتم.',
      'قبل از اینکه بتوانم با این سامانه کار کنم باید چیزهای زیادی یاد می‌گرفتم.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool fa = _isPersian;
    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        title: fa ? 'ارزیابی میدانی' : 'Field evaluation',
        scrollable: false,
        body: Column(
          children: <Widget>[
            TabBar(
              tabs: <Widget>[
                Tab(text: fa ? 'نقطه‌ی مرجع' : 'Reference point'),
                const Tab(text: 'SUS'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[_referenceForm(fa), _susForm(fa)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referenceForm(bool fa) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                fa
                    ? 'مختصات نقطه‌ی اندازه‌گیری‌شده را ثبت کنید.'
                    : 'Enter the surveyed coordinates for the reference point.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                fa
                    ? 'برای سنجش خطای GPS، این مختصات باید از یک نقطه‌ی معلوم یا اندازه‌گیری‌شده باشد؛ مختصات GPS گوشی به‌تنهایی مرجع واقعی نیست.'
                    : 'For GPS error measurement, use a known surveyed point. A phone GPS fix alone is not ground truth.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _labelController,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText:
                      fa ? 'نام نقطه (اختیاری)' : 'Point label (optional)',
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _coordinateField(
                      _latController,
                      fa ? 'عرض جغرافیایی' : 'Latitude',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _coordinateField(
                      _lngController,
                      fa ? 'طول جغرافیایی' : 'Longitude',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _capturing ? null : _fillFromGps,
                icon: _capturing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  fa
                      ? 'پرکردن تقریبی با GPS گوشی'
                      : 'Fill from approximate phone GPS',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _savingReference || _loading ? null : _saveReference,
                icon: _savingReference
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  fa ? 'ذخیره‌ی نقطه‌ی مرجع' : 'Save reference point',
                ),
              ),
              if (_referenceError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _referenceError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_referenceMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _referenceMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (_loading) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _coordinateField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _susForm(bool fa) {
    final List<String> items = _localizedSusItems();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                fa
                    ? 'پرسشنامه‌ی کاربردپذیری سامانه (SUS)'
                    : 'System Usability Scale (SUS)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                fa
                    ? 'برای هر جمله یک گزینه انتخاب کنید؛ پاسخ درست یا غلطی وجود ندارد.'
                    : 'Choose one response for each statement. There are no right or wrong answers.',
              ),
              if (_loadingSus) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
              if (_susError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _susError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _loadSusForm,
                  child: Text(fa ? 'تلاش دوباره' : 'Retry'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              for (int index = 0; index < items.length; index += 1)
                _susQuestion(index, items[index], fa),
              if (_susMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _susMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed:
                    _submittingSus || _answers.length != 10 ? null : _submitSus,
                icon: _submittingSus
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(fa ? 'ثبت پاسخ‌ها' : 'Submit responses'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _susQuestion(int index, String item, bool fa) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${index + 1}. $item',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.xs,
            children: _choices.map((int choice) {
              return ChoiceChip(
                label: Text(
                  fa ? Fa.digits(choice.toString()) : choice.toString(),
                ),
                selected: _answers[index] == choice,
                onSelected: (bool selected) {
                  setState(() {
                    if (selected) _answers[index] = choice;
                    _susMessage = null;
                  });
                },
              );
            }).toList(growable: false),
          ),
          if (index == 0)
            Text(
              fa
                  ? '۱ کاملاً مخالف  ·  ۵ کاملاً موافق'
                  : '1 Strongly disagree  ·  5 Strongly agree',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Divider(height: AppSpacing.md),
        ],
      ),
    );
  }
}
