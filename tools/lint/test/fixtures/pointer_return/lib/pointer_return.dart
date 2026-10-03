import 'dart:ffi';

class BadClass {
  Pointer<Void> getPointer() => throw UnimplementedError();
}
