import 'dart:ffi';

class _Base {
  Pointer<Void> get raw => Pointer.fromAddress(0);
}

class Exported extends _Base {}
