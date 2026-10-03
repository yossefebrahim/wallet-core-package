// ignore_for_file: unused_field
import 'dart:ffi';

/// Not exported: stores a pointer in a private field.
class Inner {
  Pointer<Void>? _p;
}

/// Not exported: a mixin that stores a pointer.
mixin Storing {
  Pointer<Void>? _m;
}
