// `package:ffi` resolves through the workspace (the SDK packages depend on
// it); the fixture needs its real library URI and adds no dependency.
// ignore_for_file: depend_on_referenced_packages, unused_field
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'src/handle.dart';

class Wrapped {
  Wrapped(this._h);

  final Handle _h;
}

class DoublyWrapped {
  DoublyWrapped(this._o);

  final Outer _o;
}

class WithArena {
  final Arena _arena = Arena();
}

class Plain {
  Plain(this._address);

  final int _address;

  int get address => Pointer<Void>.fromAddress(_address).address;
}
