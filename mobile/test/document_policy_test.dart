import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/features/settings/domain/document_policy.dart';

void main() {
  test('hides document upload for accounts that already passed verification',
      () {
    expect(DocumentPolicy.canUpload('verified'), isFalse);
    expect(DocumentPolicy.canUpload('approved'), isFalse);
    expect(DocumentPolicy.canUpload('pending'), isTrue);
    expect(DocumentPolicy.canUpload('unverified'), isTrue);
  });

  test('caps the health description at the server limit', () {
    expect(DocumentPolicy.healthConditionMaxLength, 80);
  });
}
