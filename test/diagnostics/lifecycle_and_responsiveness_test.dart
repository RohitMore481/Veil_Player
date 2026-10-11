import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/diagnostics/diagnostic_service.dart';
import 'package:veil_player/diagnostics/responsiveness_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ResponsivenessMonitor Tests', () {
    test('Starts and stops cleanly', () {
      final monitor = ResponsivenessMonitor();
      monitor.start();
      // Second start is no-op
      monitor.start();
      monitor.stop();
      // Second stop is no-op
      monitor.stop();
    });

    test('Stop resets _lastTick to prevent false stall detection across backgrounding', () {
      int stallCalls = 0;
      final monitor = ResponsivenessMonitor(
        onStallDetected: ({required observedDelay, required context}) {
          stallCalls++;
        },
      );

      monitor.start();
      // Simulate app backgrounding
      monitor.stop();

      // After resuming later, starting again should not immediately trigger stall
      monitor.start();
      expect(stallCalls, 0);
      monitor.stop();
    });
  });

  group('DiagnosticService Lifecycle State Tests', () {
    test('Transitions app states correctly on didChangeAppLifecycleState', () {
      final service = DiagnosticService.instance;

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.currentAppState, 'Background');

      service.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(service.currentAppState, 'Inactive');

      service.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(service.currentAppState, 'Detached');

      service.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(service.currentAppState, 'Hidden');

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.currentAppState, 'Foreground');
    });

    test('onAppPausedOrClosed stops monitor cleanly', () async {
      final service = DiagnosticService.instance;
      await service.onAppPausedOrClosed();
      // Should execute without throwing
      expect(service.currentAppState, isNotNull);
    });
  });
}
