import 'dart:async';

typedef OnResponsivenessStallCallback = void Function({
  required Duration observedDelay,
  required String context,
});

/// Lightweight Main-Isolate Responsiveness Monitor.
///
/// Detects main thread stalls exceeding a safe threshold (e.g. >2500ms) without
/// introducing wakeups, timers spam, or battery drain.
class ResponsivenessMonitor {
  static const Duration _checkInterval = Duration(seconds: 2);
  static const Duration stallThreshold = Duration(milliseconds: 2500);
  static const Duration _cooldownDuration = Duration(minutes: 5);

  Timer? _timer;
  DateTime? _lastTick;
  bool _isActive = false;
  DateTime? _lastReportTime;
  String _currentContext = 'Idle';

  final OnResponsivenessStallCallback? onStallDetected;

  ResponsivenessMonitor({this.onStallDetected});

  void start() {
    if (_isActive) return;
    _isActive = true;
    _lastTick = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, _onTick);
  }

  void stop() {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
    _lastTick = null;
  }

  void setContext(String context) {
    _currentContext = context;
  }

  void _onTick(Timer timer) {
    if (!_isActive) return;

    final now = DateTime.now();
    if (_lastTick != null) {
      final elapsed = now.difference(_lastTick!);
      final delayOverExpected = elapsed - _checkInterval;

      if (delayOverExpected >= stallThreshold) {
        // Main thread stall detected!
        final nowTime = DateTime.now();
        final shouldReport = _lastReportTime == null ||
            nowTime.difference(_lastReportTime!) > _cooldownDuration;

        if (shouldReport) {
          _lastReportTime = nowTime;
          onStallDetected?.call(
            observedDelay: elapsed,
            context: _currentContext,
          );
        }
      }
    }
    _lastTick = now;
  }
}
