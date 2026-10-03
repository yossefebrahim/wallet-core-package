import 'dart:ffi';

/// Not exported: its getter is only a pointer after substitution.
abstract class Box<T> {
  T get value;
}

/// Not exported: static members are not reachable through a subclass.
class Factory {
  static Pointer<Void> make() => Pointer.fromAddress(0);
}
