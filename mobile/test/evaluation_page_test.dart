import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/network/api_client.dart';
import 'package:safestep/core/storage/token_store.dart';
import 'package:safestep/features/evaluation/data/evaluation_repository.dart';
import 'package:safestep/features/evaluation/presentation/evaluation_page.dart';

class _EvaluationRepositoryStub extends EvaluationRepository {
  _EvaluationRepositoryStub()
      : super(
          ApiClient(
            tokenStore: TokenStore(const FlutterSecureStorage()),
            onSessionExpired: () {},
          ),
        );

  @override
  Future<ReferencePoint?> currentReference() async => null;

  @override
  Future<SusForm> susForm() async => const SusForm(
        items: <String>[],
        choices: <int>[1, 2, 3, 4, 5],
      );
}

void main() {
  testWidgets('field evaluation page shows reference and SUS forms', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          evaluationRepositoryProvider.overrideWithValue(
            _EvaluationRepositoryStub(),
          ),
        ],
        child: const MaterialApp(home: EvaluationPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Field evaluation'), findsOneWidget);
    expect(find.text('Save reference point'), findsOneWidget);

    await tester.tap(find.text('SUS'));
    await tester.pumpAndSettle();

    expect(find.text('System Usability Scale (SUS)'), findsOneWidget);
    expect(find.text('Submit responses'), findsOneWidget);
  });

  testWidgets('reference sample form offers open and urban environments', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          evaluationRepositoryProvider.overrideWithValue(
            _EvaluationRepositoryStub(),
          ),
        ],
        child: const MaterialApp(home: EvaluationPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder environmentSelector =
        find.byKey(const Key('evaluation-environment-selector'));
    expect(environmentSelector, findsOneWidget);
    expect(find.text('Open environment'), findsOneWidget);

    await tester.tap(environmentSelector);
    await tester.pumpAndSettle();
    expect(find.text('Urban environment'), findsOneWidget);
    await tester.tap(find.text('Urban environment').last);
    await tester.pumpAndSettle();

    expect(find.text('Urban environment'), findsOneWidget);
  });
}
