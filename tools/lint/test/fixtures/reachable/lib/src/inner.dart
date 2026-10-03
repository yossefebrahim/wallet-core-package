import 'dart:ffi';

import 'generated/gen.dart';

/// Not exported; reachable only through public signatures of the entry.
class Inner {
  Pointer<Void> get pointer => Pointer.fromAddress(0);

  GeneratedThing get generated => GeneratedThing();

  void dispose() {}

  /// A cycle: Inner → Holder → Inner.
  Holder get holder => Holder();
}

/// Not exported; reaches Inner one hop further.
class Holder {
  Inner get inner => Inner();
}

/// Not exported; a subclass of a generated class.
class Sub extends GeneratedBase {}

/// Not exported; only SDK types in its signatures.
class Plain {
  List<int> get values => const [];
}
