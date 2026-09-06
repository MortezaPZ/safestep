import 'dart:math' as math;

/// استخراج ۱۴ ویژگی — الگوریتم مشترک با نسخه‌ی JS سرور.
class FallFeatures {
  const FallFeatures._();

  static const double g = 9.80665;
  static const int windowSize = 150;
  static const int hz = 50;

  static double _mag(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  static double _mean(List<double> arr) {
    if (arr.isEmpty) return 0;
    return arr.reduce((double a, double b) => a + b) / arr.length;
  }

  static double _std(List<double> arr) {
    if (arr.length < 2) return 0;
    final double m = _mean(arr);
    final double v =
        arr.fold<double>(0, (double s, double x) => s + (x - m) * (x - m)) /
            arr.length;
    return math.sqrt(v);
  }

  static int _clip(int i, int n) {
    if (i < 0) return 0;
    if (i > n - 1) return n - 1;
    return i;
  }

  static List<double> extract({
    required List<List<double>> acc,
    required List<List<double>> gyro,
  }) {
    final List<List<double>> a =
        acc.length >= windowSize ? acc.sublist(0, windowSize) : acc;
    final List<List<double>> gy =
        gyro.length >= windowSize ? gyro.sublist(0, windowSize) : gyro;
    final List<double> smv = a
        .map((List<double> s) => _mag(s[0], s[1], s[2]) / g)
        .toList(growable: false);

    int peak = 0;
    for (int i = 1; i < smv.length; i++) {
      if (smv[i] > smv[peak]) peak = i;
    }

    final double smvMax = smv.isEmpty ? 0 : smv[peak];
    final double smvMin = smv.isEmpty ? 0 : smv.reduce(math.min);
    final double smvMean = _mean(smv);
    final double smvStd = _std(smv);
    final double smvRange = smvMax - smvMin;
    final double impactIndexRatio = peak / windowSize;

    final int preStart = _clip(peak - (0.5 * hz).round(), smv.length);
    final double preImpactMean = _mean(smv.sublist(preStart, peak));

    final int postA = _clip(peak + hz, smv.length);
    final int postB = _clip(peak + 2 * hz, smv.length);
    final List<double> postWin =
        smv.sublist(postA, math.max(postA + 1, postB));
    final double postImpactMean = _mean(postWin);
    final double postImpactStd = _std(postWin);

    final int ffStart = _clip(peak - (0.4 * hz).round(), smv.length);
    final List<double> ff = smv.sublist(ffStart, peak == ffStart ? peak + 1 : peak);
    final double freeFallMinBeforePeak = ff.reduce(math.min);

    final List<double> gyroMag =
        gy.map((List<double> s) => _mag(s[0], s[1], s[2])).toList();
    final double gyroMax =
        gyroMag.isEmpty ? 0 : math.max(0, gyroMag.reduce(math.max));
    final List<double> gyroPost =
        gyroMag.sublist(postA, math.max(postA + 1, postB));
    final double gyroMeanPost = _mean(gyroPost);

    final List<List<double>> first = a.sublist(0, math.min(a.length, (0.5 * hz).round()));
    final List<List<double>> last = a.sublist(math.max(0, a.length - (0.5 * hz).round()));
    final List<double> m1 = <double>[
      _mean(first.map((List<double> s) => s[0]).toList()),
      _mean(first.map((List<double> s) => s[1]).toList()),
      _mean(first.map((List<double> s) => s[2]).toList()),
    ];
    final List<double> m2 = <double>[
      _mean(last.map((List<double> s) => s[0]).toList()),
      _mean(last.map((List<double> s) => s[1]).toList()),
      _mean(last.map((List<double> s) => s[2]).toList()),
    ];
    final double n1 = _mag(m1[0], m1[1], m1[2]) == 0 ? 1 : _mag(m1[0], m1[1], m1[2]);
    final double n2 = _mag(m2[0], m2[1], m2[2]) == 0 ? 1 : _mag(m2[0], m2[1], m2[2]);
    final double dot =
        (m1[0] / n1) * (m2[0] / n2) + (m1[1] / n1) * (m2[1] / n2) + (m1[2] / n1) * (m2[2] / n2);
    final double orientationChangeDeg =
        (math.acos(dot.clamp(-1, 1)) * 180) / math.pi;

    int zeroCrossingsSmv = 0;
    for (int i = 1; i < smv.length; i++) {
      final double a0 = smv[i - 1] - 1;
      final double a1 = smv[i] - 1;
      if ((a0 < 0 && a1 >= 0) || (a0 > 0 && a1 <= 0)) {
        zeroCrossingsSmv += 1;
      }
    }

    return <double>[
      smvMax,
      smvMin,
      smvMean,
      smvStd,
      smvRange,
      impactIndexRatio,
      preImpactMean,
      postImpactMean,
      postImpactStd,
      freeFallMinBeforePeak,
      gyroMax,
      gyroMeanPost,
      orientationChangeDeg,
      zeroCrossingsSmv.toDouble(),
    ];
  }

  static bool preScreen(List<double> features) {
    final double smvMax = features[0];
    final double freeFallMinBeforePeak = features[9];
    final double orientationChangeDeg = features[12];
    return smvMax >= 2.3 &&
        (freeFallMinBeforePeak <= 0.6 || orientationChangeDeg >= 45);
  }
}
