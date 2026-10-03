import 'dart:ffi';

import 'src/aliases.dart';
import 'src/generated/ids.dart';

class Aliased {
  RawHandle get handle => Pointer.fromAddress(0);

  Handles<Pointer<Uint8>> get handles => const [];

  GeneratedId get id => 0;

  PublicId get chained => 0;
}
