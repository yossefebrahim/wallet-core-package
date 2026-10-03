import 'dart:ffi';

/// Not exported: a `Pointer` behind an extension type.
extension type Handle(Pointer<Void> _pointer) {}

/// Not exported: an extension type wrapping another one.
extension type Outer(Handle _handle) {}
