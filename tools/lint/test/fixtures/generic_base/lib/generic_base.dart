import 'dart:ffi';

import 'src/base.dart';

abstract class PointerBox extends Box<Pointer<Void>> {}

class Made extends Factory {}

class OwnStatic {
  static Pointer<Void> own() => Pointer.fromAddress(0);
}
