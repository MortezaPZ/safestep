import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/sos/presentation/sos_button.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('دکمه‌ی اضطراری با یک ضربه ارسال نمی‌شود', (WidgetTester tester) async {
    await tester.pumpWidget(await wrapForTest(const SosButton()));
    await tester.pump();

    expect(find.text('نگه دارید'), findsOneWidget);

    await tester.tap(find.text('درخواست کمک'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('نگه دارید'), findsOneWidget);
    expect(find.textContaining('ثانیه‌ی دیگر'), findsNothing);
  });
}
