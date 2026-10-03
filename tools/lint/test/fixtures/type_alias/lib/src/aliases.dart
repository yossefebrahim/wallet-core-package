import 'dart:ffi';

import 'generated/ids.dart';

/// Not exported: only reachable through the signatures that use it.
typedef RawHandle = Pointer<Void>;

/// Not exported: generic alias whose argument carries the pointer.
typedef Handles<T> = List<T>;

/// Not exported: a typedef chain ending in a generated typedef.
typedef PublicId = GeneratedId;
