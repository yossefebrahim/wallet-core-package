import 'src/inner.dart';

/// Implements the interface only: stores nothing of Inner's.
class Implementing implements Inner {}

/// Extends: inherits the stored field.
class Extending extends Inner {}

/// Mixes in: inherits the stored field.
class Mixing with Storing {}
