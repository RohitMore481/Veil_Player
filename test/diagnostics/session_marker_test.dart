import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/diagnostics/session_marker_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late SessionMarkerManager markerManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_marker_test_');
    markerManager = SessionMarkerManager(diagnosticsDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SessionMarkerManager Evaluation Tests', () {
    test('Evaluates firstRun when no markers exist', () async {
      final evaluation = await markerManager.evaluatePreviousSession();
      expect(evaluation.outcome, equals(PreviousSessionOutcome.firstRun));
      expect(evaluation.hasConfirmedCrash, isFalse);
      expect(evaluation.crashData, isNull);
    });

    test('Evaluates cleanExit when session_lifecycle.json has clean_exit', () async {
      final lifecycleFile = File('${tempDir.path}/session_lifecycle.json');
      await lifecycleFile.writeAsString(jsonEncode({
        'sessionId': 'sess_1',
        'state': 'clean_exit',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));

      final evaluation = await markerManager.evaluatePreviousSession();
      expect(evaluation.outcome, equals(PreviousSessionOutcome.cleanExit));
      expect(evaluation.hasConfirmedCrash, isFalse);
      expect(evaluation.previousSessionId, equals('sess_1'));
    });

    test('Evaluates backgroundTerminated when session was paused/background', () async {
      final lifecycleFile = File('${tempDir.path}/session_lifecycle.json');
      await lifecycleFile.writeAsString(jsonEncode({
        'sessionId': 'sess_2',
        'state': 'background',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));

      final evaluation = await markerManager.evaluatePreviousSession();
      expect(evaluation.outcome, equals(PreviousSessionOutcome.backgroundTerminated));
      expect(evaluation.hasConfirmedCrash, isFalse);
      expect(evaluation.crashData, isNull);
    });

    test('Evaluates unresolvedTermination when session was foreground without crash evidence', () async {
      final lifecycleFile = File('${tempDir.path}/session_lifecycle.json');
      await lifecycleFile.writeAsString(jsonEncode({
        'sessionId': 'sess_3',
        'state': 'foreground',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));

      final evaluation = await markerManager.evaluatePreviousSession();
      expect(evaluation.outcome, equals(PreviousSessionOutcome.unresolvedTermination));
      expect(evaluation.hasConfirmedCrash, isFalse);
      expect(evaluation.crashData, isNull);
    });

    test('Evaluates confirmedCrash when confirmed_crash_marker.json exists', () async {
      await markerManager.recordConfirmedCrash(
        sessionId: 'sess_crash',
        errorType: 'DART_FATAL_ERROR',
        exception: 'StateError: Bad state in test isolate',
        stackTrace: 'line 1\nline 2',
      );

      final evaluation = await markerManager.evaluatePreviousSession();
      expect(evaluation.outcome, equals(PreviousSessionOutcome.confirmedCrash));
      expect(evaluation.hasConfirmedCrash, isTrue);
      expect(evaluation.crashData, isNotNull);
      expect(evaluation.crashData!.exception, contains('Bad state'));
      expect(evaluation.crashData!.errorType, equals('DART_FATAL_ERROR'));

      // Check marker was consumed/cleared so subsequent evaluation does not report it again
      final secondEvaluation = await markerManager.evaluatePreviousSession();
      expect(secondEvaluation.hasConfirmedCrash, isFalse);
    });

    test('updateLifecycleState writes and updates state cleanly', () async {
      await markerManager.updateLifecycleState(
        sessionId: 'sess_life',
        state: 'foreground',
      );

      final lifecycleFile = File('${tempDir.path}/session_lifecycle.json');
      expect(await lifecycleFile.exists(), isTrue);

      final data1 = jsonDecode(await lifecycleFile.readAsString());
      expect(data1['state'], equals('foreground'));

      await markerManager.updateLifecycleState(
        sessionId: 'sess_life',
        state: 'paused',
      );
      final data2 = jsonDecode(await lifecycleFile.readAsString());
      expect(data2['state'], equals('paused'));
    });

    test('Normal immediate relaunch does not produce false confirmed crash', () async {
      // 1. App started in foreground
      await markerManager.updateLifecycleState(sessionId: 'sess_quick', state: 'foreground');
      // 2. App backgrounded normally
      await markerManager.updateLifecycleState(sessionId: 'sess_quick', state: 'background');
      // 3. User immediately relaunches app
      final evaluation = await markerManager.evaluatePreviousSession();
      expect(evaluation.outcome, equals(PreviousSessionOutcome.backgroundTerminated));
      expect(evaluation.hasConfirmedCrash, isFalse);
    });
  });
}
