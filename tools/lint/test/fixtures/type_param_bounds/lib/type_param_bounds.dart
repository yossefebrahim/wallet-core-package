import 'dart:ffi';

class Bounded<T extends Pointer<Void>> {}

class Holder {
  void take<T extends Pointer<Uint8>>(Object value) {}
}

typedef Callback<T extends Pointer<Int8>> = void Function(Object value);

void run<T extends Pointer<Int16>>() {}
