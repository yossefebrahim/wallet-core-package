import 'dart:async';

class LintError implements Exception {
  const LintError(this.message);

  final String message;

  @override
  String toString() => message;
}

class Version implements Comparable<Version> {
  const Version(this.major);

  final int major;

  @override
  int compareTo(Version other) => major.compareTo(other.major);
}

enum Mode { fast, safe }

class Numbers extends Iterable<int> {
  @override
  Iterator<int> get iterator => const <int>[].iterator;
}

abstract class Ticks extends Stream<int> {}

abstract class Pending implements Future<String> {}

extension type const Amount(int value) implements int {}
