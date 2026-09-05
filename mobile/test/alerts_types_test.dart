import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/alerts/data/alerts_repository.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('هفت نوع هشدار برچسب و آیکون فارسی دارند', (WidgetTester tester) async {
    const List<String> types = <String>[
      'sos',
      'zone_exit',
      'zone_enter',
      'long_stop',
      'gps_lost',
      'low_battery',
      'fall_detected',
    ];

    await tester.pumpWidget(
      await wrapForTest(
        ListView(
          children: types.map((String type) {
            final AlertItem item = AlertItem(
              id: type,
              type: type,
              severity: type == 'sos' || type == 'fall_detected' ? 'critical' : 'warning',
              title: 't',
              body: 'b',
              createdAt: DateTime.utc(2026, 1, 1),
            );
            return ListTile(
              leading: Icon(_iconFor(type)),
              title: Text(item.typeLabel),
            );
          }).toList(),
        ),
      ),
    );

    expect(find.text('درخواست کمک'), findsOneWidget);
    expect(find.text('خروج از محدوده'), findsOneWidget);
    expect(find.text('بازگشت به محدوده'), findsOneWidget);
    expect(find.text('توقف طولانی'), findsOneWidget);
    expect(find.text('قطع موقعیت'), findsOneWidget);
    expect(find.text('باتری کم'), findsOneWidget);
    expect(find.text('تشخیص سقوط'), findsOneWidget);
    expect(find.byIcon(Icons.personal_injury_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sos_rounded), findsOneWidget);
  });
}

IconData _iconFor(String type) {
  switch (type) {
    case 'sos':
      return Icons.sos_rounded;
    case 'zone_exit':
      return Icons.exit_to_app_rounded;
    case 'zone_enter':
      return Icons.home_rounded;
    case 'long_stop':
      return Icons.hourglass_bottom_rounded;
    case 'gps_lost':
      return Icons.gps_off_rounded;
    case 'low_battery':
      return Icons.battery_alert_rounded;
    case 'fall_detected':
      return Icons.personal_injury_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}
