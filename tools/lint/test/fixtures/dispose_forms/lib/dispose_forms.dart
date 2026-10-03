class Wallet {}

extension SyncClose on Wallet {
  void dispose() {}
}

class GetterDispose {
  void Function() get dispose => () {};
}

class FieldDispose {
  FieldDispose(this.dispose);

  final void Function() dispose;
}

class Closer {
  void call() {}
}

class CallableDispose {
  Closer get dispose => Closer();
}

class NotCallable {
  int get dispose => 0;
}
