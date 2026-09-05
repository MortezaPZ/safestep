import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/utils/fa.dart';
import 'package:safestep/features/auth/presentation/login_page.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('صفحه‌ی ورود رندر می‌شود و شماره‌ی ناقص را رد می‌کند', (WidgetTester tester) async {
    await tester.pumpWidget(await wrapForTest(const LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('خوش برگشتید'), findsOneWidget);
    expect(find.text('شماره موبایل'), findsOneWidget);
    expect(Fa.isValidPhone('0912'), isFalse);

    await tester.enterText(find.byType(TextField).first, '0912');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.textContaining('شماره موبایل را کامل'), findsOneWidget);
  });
}
