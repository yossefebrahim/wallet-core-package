import 'package:test/test.dart';
import 'package:wallet_core_flutter_bindings/wallet_core_flutter_bindings.dart';

void main() {
  test('packageName names this package', () {
    expect(packageName, 'wallet_core_flutter_bindings');
  });
}
