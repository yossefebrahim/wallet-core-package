class Base {
  void dispose() {}
}

class Exported extends Base {}

mixin _Closeable {
  void dispose() {}
}

class WithMixin with _Closeable {}

abstract interface class _Releasable {
  void dispose();
}

class Overriding implements _Releasable {
  @override
  void dispose() {}
}
