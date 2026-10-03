import 'dart:async';
import 'dart:ffi';

class Complex {
  Future<Pointer<Void>> get futurePointer async => Pointer.fromAddress(0);
  Pointer<Void>? get nullablePointer => null;
  void recordParam(({Pointer<Void> p}) rec) {}
  void functionParam(void Function(Pointer<Void>) cb) {}
}
