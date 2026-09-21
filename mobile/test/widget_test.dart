import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/network/server_origin.dart';

void main() {
  test('نرمال‌سازی آدرس سرور', () {
    expect(ServerOrigin.normalize('192.168.1.10:4000'), 'http://192.168.1.10:4000');
    expect(ServerOrigin.normalize('http://192.168.1.10:4000/'), 'http://192.168.1.10:4000');
  });
}
