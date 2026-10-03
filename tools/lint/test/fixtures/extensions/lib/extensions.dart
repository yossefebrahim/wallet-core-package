import 'dart:ffi';

extension X on String {
  Pointer<Void> toNative() => Pointer.fromAddress(0);
}

extension type Handle(Pointer<Void> _p) {}
