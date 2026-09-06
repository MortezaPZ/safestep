import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/fall/data/fall_repository.dart';
import 'package:safestep/features/fall/presentation/fall_check_page.dart';

import 'test_helpers.dart';

class _FakeFalls extends FallRepository {
  String? lastFeedback;

  @override
  Future<void> feedback({
    required String id,
    required String feedback,
    int? respondedWithinSec,
  }) async {
    lastFeedback = feedback;
  }
}

void main() {
  testWidgets('شمارش معکوس no_response می‌فرستد', (WidgetTester tester) async {
    final _FakeFalls fake = _FakeFalls();
    await tester.pumpWidget(
      await wrapForTest(
        const FallCheckPage(fallEventId: 'evt', countdownSec: 1),
        overrides: <Override>[
          fallRepositoryProvider.overrideWithValue(fake),
        ],
      ),
    );
    expect(find.text('آیا حال شما خوب است؟'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(fake.lastFeedback, 'no_response');
  });
}
