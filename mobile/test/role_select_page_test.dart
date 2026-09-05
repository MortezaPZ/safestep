import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/onboarding/presentation/role_select_page.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('صفحه‌ی انتخاب نقش هر دو مسیر را نشان می‌دهد', (WidgetTester tester) async {
    await tester.pumpWidget(await wrapForTest(const RoleSelectPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('خوش آمدید'), findsOneWidget);
    expect(find.text('خودم استفاده می‌کنم'), findsOneWidget);
    expect(find.text('مراقب یکی از عزیزانم هستم'), findsOneWidget);
  });
}
