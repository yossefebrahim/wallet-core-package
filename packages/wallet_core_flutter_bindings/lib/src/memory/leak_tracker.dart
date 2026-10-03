/// [LeakTracker]: the debug-only report of handles that were collected without
/// ever being disposed (PRD §11.2 item 7).
library;

import 'native_context.dart';
import 'native_resource.dart';

/// One tracked resource: what it was, where it was created, and what became
/// of it.
///
/// A record carries **identity and provenance only** — an id, a Dart type name,
/// and the stack trace of the allocation site. It never carries the resource's
/// contents, its native pointer, or its length, because a handle may hold key
/// material and a diagnostic record is exactly the thing that reaches a log or
/// a crash report (threat model TM-11, TM-31).
final class LeakRecord {
  LeakRecord._(
    this.id,
    this.resourceType,
    this.allocationStackTrace,
    this._ref,
  );

  /// Serial number within the tracker that created this record.
  ///
  /// Unique and monotonic per tracker, and the token the managed [Finalizer]
  /// carries. It is a number and nothing else: a token that referred to the
  /// resource would keep the resource alive and the collection this record
  /// exists to observe would never happen.
  final int id;

  /// The Dart type of the resource, e.g. `'TWDataHandle'`.
  final String resourceType;

  /// Where the resource was created — `StackTrace.current` taken in the
  /// constructor.
  ///
  /// This is the whole point of the record: it names the call site that forgot
  /// to dispose. A Dart stack trace carries function names, files, and line
  /// numbers, never argument values (threat model TM-11).
  final StackTrace allocationStackTrace;

  final WeakReference<NativeResource> _ref;

  bool _disposed = false;
  bool _finalizedWithoutDispose = false;

  /// The resource, if it is still reachable, and `null` once the collector has
  /// taken it.
  ///
  /// The reference is **weak**: a tracker never keeps alive the thing it is
  /// tracking. For a record in [LeakReport.leaks] this is always `null` — the
  /// record is only there because the resource is gone.
  NativeResource? get resource => _ref.target;

  /// Whether `dispose()` was called on the resource.
  bool get isDisposed => _disposed;

  /// Whether the resource was collected without ever being disposed.
  ///
  /// The native memory was still freed — [NativeResource]'s own
  /// `NativeFinalizer` did that — so this is a report of a missed `dispose()`,
  /// not of leaked bytes. What was missed matters anyway: disposal is what
  /// makes upstream wipe the buffer at a moment the code chooses, rather than
  /// whenever the collector gets round to it (PRD §11.1, §11.2 item 1).
  bool get isFinalizedWithoutDispose => _finalizedWithoutDispose;

  /// Type, id, and — for a leak — the allocation stack trace. Nothing else.
  @override
  String toString() {
    final state = _finalizedWithoutDispose
        ? 'finalized without dispose'
        : _disposed
        ? 'disposed'
        : 'live';
    final buffer = StringBuffer('#$id $resourceType ($state)');
    if (_finalizedWithoutDispose) {
      buffer.writeln();
      buffer.writeln('    created at:');
      for (final line in allocationStackTrace.toString().trimRight().split(
        '\n',
      )) {
        buffer.writeln('      ${line.trim()}');
      }
    }
    return buffer.toString().trimRight();
  }
}

/// A snapshot of one [LeakTracker]'s accounting.
///
/// Counts and type names only, plus the allocation stack trace of each leak.
/// Nothing here is derived from a resource's contents or its pointer
/// (threat model TM-31).
final class LeakReport {
  LeakReport._({
    required this.live,
    required this.disposed,
    required this.finalizedWithoutDispose,
    required this.liveByType,
    required this.leaks,
    required this.stopped,
  });

  /// Resources created, not yet disposed, and not yet collected.
  final int live;

  /// Resources whose `dispose()` ran.
  final int disposed;

  /// Resources collected without `dispose()` ever being called — the leak
  /// count.
  final int finalizedWithoutDispose;

  /// How many live resources there are of each Dart type.
  final Map<String, int> liveByType;

  /// One record per resource counted in [finalizedWithoutDispose].
  final List<LeakRecord> leaks;

  /// Whether the tracker had been stopped when this report was taken.
  final bool stopped;

  /// Counts, live types, and each leak's type and allocation stack trace.
  ///
  /// **Nothing else.** A test asserts that a report taken while a handle over
  /// known bytes is live contains neither those bytes nor their hex
  /// (threat model TM-31).
  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('LeakReport(live: $live, disposed: $disposed, ')
      ..write('finalizedWithoutDispose: $finalizedWithoutDispose');
    if (stopped) buffer.write(', stopped');
    buffer.writeln(')');
    for (final entry in liveByType.entries) {
      buffer.writeln('  live ${entry.key}: ${entry.value}');
    }
    for (final leak in leaks) {
      buffer.writeln('  leak $leak');
    }
    return buffer.toString().trimRight();
  }
}

/// Counts the native handles created against a context, and reports the ones
/// the collector took before anybody disposed them (PRD §11.2 item 7).
///
/// **Debug builds only, by construction.** The only way to obtain one is
/// [maybeCreate], whose body constructs it inside an `assert`. With assertions
/// disabled — a release build — the constructor is never reached from anywhere,
/// nothing in the program refers to this class, and tree shaking removes it
/// along with the records and the report (PRD §16 S8, threat model TM-30). That
/// is the mechanism: not a `kDebugMode` check that a reader has to trust, but
/// an unreachable constructor. The release-mode proof — a compiled program
/// showing [maybeCreate] returns `null` — belongs to **T1.17**, which owns the
/// release-mode CI gate; the tests in this package run under `dart test`, where
/// assertions are on, and prove the debug-mode behaviour.
///
/// **What it observes, and what it cannot.** Creation and disposal are exact:
/// they are reported by [NativeResource] itself through the [ResourceObserver]
/// seam. Collection is not: a Dart `Finalizer` runs "as early as possible"
/// after an object becomes unreachable and is guaranteed only at isolate-group
/// shutdown, and it does not run at all on a killed process (PRD §11.1
/// [VERIFIED]). So [LeakReport.finalizedWithoutDispose] is a lower bound that
/// grows as the collector runs, and a report that shows no leaks is not a proof
/// that there are none. This is a diagnostic, not a guarantee.
///
/// The tracker's `Finalizer` is a **managed** one (`dart:core`), attached
/// alongside — never instead of — the `NativeFinalizer` that frees the native
/// object. It observes; it releases nothing.
///
/// A tracker keeps nothing alive: each record holds a [WeakReference] to its
/// resource and an integer finalizer token.
///
/// Call [stop] when the thing being tracked is shut down. After that, nothing
/// changes any count: a resource released by shutting a session down and
/// collected afterwards is not a missed `dispose()` and is not counted as one
/// (DECISION-12 §5).
///
/// One tracker belongs to the isolate whose resources it tracks, like the
/// handles themselves.
final class LeakTracker implements ResourceObserver {
  /// Private on purpose: [maybeCreate] is the only door, and it is behind an
  /// assert.
  LeakTracker._();

  /// A tracker in a debug build, `null` in a release build.
  ///
  /// ```dart
  /// final context = NativeContext(
  ///   bindings,
  ///   observer: LeakTracker.maybeCreate() ?? const NoopResourceObserver(),
  /// );
  /// ```
  ///
  /// The construction happens inside an `assert`, so with assertions disabled
  /// the expression is removed, this method returns `null`, and no code path in
  /// the program can produce a [LeakTracker] — which is what lets the compiler
  /// drop the class entirely (threat model TM-30).
  static LeakTracker? maybeCreate() {
    LeakTracker? tracker;
    assert(() {
      tracker = LeakTracker._();
      return true;
    }());
    return tracker;
  }

  /// Records by id. Ids are handed out in creation order.
  final Map<int, LeakRecord> _records = <int, LeakRecord>{};

  /// The id of each resource still alive, so that disposal finds its record in
  /// constant time.
  ///
  /// An [Expando] rather than a `Map` keyed on the resource: an expando holds
  /// its keys **weakly**, so this lookup table does not keep alive the very
  /// objects whose collection the tracker exists to observe.
  final Expando<int> _ids = Expando<int>('LeakTracker');

  /// Detects collection without disposal. Managed, not native: its callback is
  /// Dart code, and it frees nothing.
  late final Finalizer<int> _finalizer = Finalizer<int>(_onFinalized);

  int _nextId = 1;
  bool _stopped = false;
  LeakReport? _frozen;

  /// Whether [stop] has been called.
  bool get isStopped => _stopped;

  /// What the tracker has seen so far, or the frozen snapshot taken by [stop].
  LeakReport get report => _frozen ?? _buildReport();

  @override
  void onResourceCreated(NativeResource resource) {
    if (_stopped) return;
    final id = _nextId++;
    _records[id] = LeakRecord._(
      id,
      // `runtimeType` and nothing else: the observer contract forbids calling
      // anything a subclass defines, and a length or a pointer would be
      // provenance this record has no business holding (TM-31).
      resource.runtimeType.toString(),
      StackTrace.current,
      WeakReference<NativeResource>(resource),
    );
    _ids[resource] = id;
    // The token is the id. Attaching the resource, or anything reachable from
    // it, would keep it alive for ever.
    _finalizer.attach(resource, id);
  }

  @override
  void onResourceDisposed(NativeResource resource) {
    if (_stopped) return;
    final id = _ids[resource];
    // No id: the resource was created before this tracker was attached, or
    // while it was stopped. Nothing to count, and nothing to complain about —
    // an observer must not throw on the disposal path.
    if (id == null) return;
    _records[id]?._disposed = true;
  }

  /// Stops all accounting and freezes [report].
  ///
  /// Idempotent. After it, creation, disposal, and collection callbacks change
  /// nothing, and the finalizer entries still attached simply do nothing when
  /// they fire. This is what a session calls when it shuts down: shutdown
  /// released every handle it owned, so a proxy or a wrapper collected
  /// afterwards is not a leak and must not be counted as one (DECISION-12 §5).
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _frozen = _buildReport();
  }

  void _onFinalized(int id) {
    if (_stopped) return;
    final record = _records[id];
    if (record == null || record._disposed) return;
    record._finalizedWithoutDispose = true;
  }

  LeakReport _buildReport() {
    var live = 0;
    var disposed = 0;
    var leaked = 0;
    final liveByType = <String, int>{};
    final leaks = <LeakRecord>[];
    for (final record in _records.values) {
      if (record._finalizedWithoutDispose) {
        leaked++;
        leaks.add(record);
      } else if (record._disposed) {
        disposed++;
      } else {
        live++;
        liveByType[record.resourceType] =
            (liveByType[record.resourceType] ?? 0) + 1;
      }
    }
    return LeakReport._(
      live: live,
      disposed: disposed,
      finalizedWithoutDispose: leaked,
      liveByType: Map<String, int>.unmodifiable(liveByType),
      leaks: List<LeakRecord>.unmodifiable(leaks),
      stopped: _stopped,
    );
  }
}
