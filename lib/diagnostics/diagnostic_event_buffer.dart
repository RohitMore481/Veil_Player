import 'dart:collection';
import 'diagnostic_event.dart';

/// Bounded, in-memory circular event buffer for Veil Player diagnostics.
///
/// Keeps approximately 100-200 recent meaningful diagnostic events in memory.
/// Never writes events to disk during normal operation.
class DiagnosticEventBuffer {
  final int capacity;
  final Queue<DiagnosticEvent> _queue = ListQueue<DiagnosticEvent>();

  DiagnosticEventBuffer({this.capacity = 150});

  /// Adds a new event to the circular buffer.
  /// Discards the oldest event if capacity is exceeded.
  void add(DiagnosticEvent event) {
    if (_queue.length >= capacity) {
      _queue.removeFirst();
    }
    _queue.add(event);
  }

  /// Returns a snapshot copy of all events currently in the buffer, ordered from oldest to newest.
  List<DiagnosticEvent> getEvents() {
    return List<DiagnosticEvent>.from(_queue);
  }

  /// Returns recent events optionally filtered by category or session ID.
  List<DiagnosticEvent> getRecentEvents({
    int count = 50,
    DiagnosticCategory? categoryFilter,
    String? playbackSessionId,
  }) {
    Iterable<DiagnosticEvent> filtered = _queue;

    if (categoryFilter != null) {
      filtered = filtered.where((e) => e.category == categoryFilter);
    }
    if (playbackSessionId != null) {
      filtered = filtered.where((e) => e.playbackSessionId == playbackSessionId || e.playbackSessionId == null);
    }

    final list = filtered.toList();
    if (list.length > count) {
      return list.sublist(list.length - count);
    }
    return list;
  }

  /// Current number of events in buffer.
  int get length => _queue.length;

  /// Clears all events in the buffer.
  void clear() {
    _queue.clear();
  }
}
