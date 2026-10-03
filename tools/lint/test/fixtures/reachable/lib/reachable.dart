// The private class below is the point of the fixture: a type that is not
// exported but is reachable through a public member.
// ignore_for_file: library_private_types_in_public_api
import 'dart:ffi';

import 'src/inner.dart';

class Direct {
  Inner get inner => Inner();
}

Future<Inner> later() async => Inner();

void bounded<T extends Inner>() {}

class Items extends Iterable<Inner> {
  @override
  Iterator<Inner> get iterator => const <Inner>[].iterator;
}

typedef InnerAlias = Inner;

class TwoHops {
  Holder get holder => Holder();
}

class SubUser {
  Sub get sub => Sub();
}

class PrivateUser {
  _Private get private => _Private();
}

class _Private {
  Pointer<Void> get raw => Pointer.fromAddress(0);
}

class SdkOnly {
  Plain get plain => Plain();

  Map<String, List<int>> get table => const {};
}

class ExportedUser {
  Direct get direct => Direct();
}
