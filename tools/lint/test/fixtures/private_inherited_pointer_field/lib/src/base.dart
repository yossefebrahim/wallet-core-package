// ignore_for_file: unused_field
import 'dart:ffi';

/// Not exported: only reachable as the superclass of exported types.
class HandleBase {
  Pointer<Void>? _handle;
}

/// Not exported: the field type is only known after substitution.
class SlotBase<T> {
  T? _slot;
}

/// Not exported: a computed private getter stores no pointer.
class ComputedBase {
  Pointer<Void> get _computed => Pointer.fromAddress(0);

  int get address => _computed.address;
}
