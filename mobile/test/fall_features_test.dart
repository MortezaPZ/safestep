import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/fall/domain/fall_features.dart';

void main() {
  test('ویژگی‌ها با vectors.json یکی هستند', () {
    final File file = File('test/fixtures/vectors.json');
    final Map<String, dynamic> raw =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final List<dynamic> cases = raw['cases'] as List<dynamic>;
    for (final dynamic item in cases) {
      final Map<String, dynamic> c = item as Map<String, dynamic>;
      final List<List<double>> acc = (c['acc'] as List<dynamic>)
          .map((dynamic s) {
            final Map<String, dynamic> m = s as Map<String, dynamic>;
            return <double>[
              (m['ax'] as num).toDouble(),
              (m['ay'] as num).toDouble(),
              (m['az'] as num).toDouble(),
            ];
          })
          .toList();
      final List<List<double>> gyro = (c['gyro'] as List<dynamic>)
          .map((dynamic s) {
            final Map<String, dynamic> m = s as Map<String, dynamic>;
            return <double>[
              (m['gx'] as num).toDouble(),
              (m['gy'] as num).toDouble(),
              (m['gz'] as num).toDouble(),
            ];
          })
          .toList();
      final List<double> expected = (c['features'] as List<dynamic>)
          .map((dynamic n) => (n as num).toDouble())
          .toList();
      final List<double> got = FallFeatures.extract(acc: acc, gyro: gyro);
      expect(got.length, 14);
      for (int i = 0; i < 14; i++) {
        expect((got[i] - expected[i]).abs(), lessThan(1e-6), reason: 'f$i');
      }
    }
  });

  test('آستانهٔ پیش‌غربال', () {
    expect(
      FallFeatures.preScreen(
        <double>[3, 0.2, 1, 0.5, 2.8, 0.3, 0.4, 1, 0.05, 0.4, 5, 0.1, 80, 4],
      ),
      isTrue,
    );
    expect(
      FallFeatures.preScreen(
        <double>[1.4, 0.9, 1.1, 0.1, 0.5, 0.2, 1.1, 1.1, 0.1, 0.95, 1, 0.8, 5, 20],
      ),
      isFalse,
    );
  });
}
