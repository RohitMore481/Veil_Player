import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Classification of previous session's termination outcome.
enum PreviousSessionOutcome {
  /// Confirmed fatal exception caught by Dart/Flutter or native crash hook.
  confirmedCrash,

  /// Clean normal exit signaled by detached / app shutdown.
  cleanExit,

  /// Normal OS process reclamation while the app was backgrounded/paused.
  backgroundTerminated,

  /// Unresolved session termination (e.g. user swiped away from Recents, OS kill).
  /// Not proof of a crash; must NOT be reported as a crash.
  unresolvedTermination,

  /// First run or no previous session data found.
  firstRun,
}

/// Details of a confirmed fatal crash.
class ConfirmedCrashData {
  final String sessionId;
  final DateTime timestamp;
  final String errorType;
  final String exception;
  final String? stackTrace;

  const ConfirmedCrashData({
    required this.sessionId,
    required this.timestamp,
    required this.errorType,
    required this.exception,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'errorType': errorType,
        'exception': exception,
        'stackTrace': stackTrace,
      };

  factory ConfirmedCrashData.fromJson(Map<String, dynamic> json) =>
      ConfirmedCrashData(
        sessionId: json['sessionId'] as String? ?? 'UNKNOWN',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        errorType: json['errorType'] as String? ?? 'FATAL_ERROR',
        exception: json['exception'] as String? ?? 'Unknown error',
        stackTrace: json['stackTrace'] as String?,
      );
}

/// Evaluation result for a previous session.
class PreviousSessionEvaluation {
  final PreviousSessionOutcome outcome;
  final ConfirmedCrashData? crashData;
  final String? previousSessionId;

  const PreviousSessionEvaluation({
    required this.outcome,
    this.crashData,
    this.previousSessionId,
  });

  bool get hasConfirmedCrash => outcome == PreviousSessionOutcome.confirmedCrash;
}

/// Manages session lifecycle and crash markers to prevent false crash reports.
///
/// Distinguishes confirmed fatal errors from normal background termination or
/// user task removal from Recents.
class SessionMarkerManager {
  static const _channel = MethodChannel('veil_player/media');
  Directory? _diagnosticsDir;

  SessionMarkerManager({Directory? diagnosticsDir})
      : _diagnosticsDir = diagnosticsDir;

  Future<Directory> _getDir() async {
    if (_diagnosticsDir != null) return _diagnosticsDir!;
    String? basePath;
    try {
      basePath = await _channel.invokeMethod<String>('getAppPrivateDirectory');
    } catch (_) {}

    basePath ??= Directory.systemTemp.path;
    final dir = Directory('$basePath/veil_diagnostics/markers');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _diagnosticsDir = dir;
    return dir;
  }

  File _getCrashMarkerFile(Directory dir) =>
      File('${dir.path}/confirmed_crash_marker.json');

  File _getLifecycleMarkerFile(Directory dir) =>
      File('${dir.path}/session_lifecycle.json');

  /// Evaluates previous session state on app startup.
  Future<PreviousSessionEvaluation> evaluatePreviousSession() async {
    try {
      final dir = await _getDir();

      // 1. Check for confirmed native Android crash marker
      try {
        final nativeMarker = await _channel.invokeMethod<String>('getNativeCrashMarker');
        if (nativeMarker != null && nativeMarker.isNotEmpty) {
          await _channel.invokeMethod('clearNativeCrashMarker');
          final parts = nativeMarker.split(':');
          final crashData = ConfirmedCrashData(
            sessionId: 'NATIVE',
            timestamp: DateTime.now(),
            errorType: 'NATIVE_UNCAUGHT_EXCEPTION',
            exception: parts.length > 2 ? parts[2] : nativeMarker,
          );
          return PreviousSessionEvaluation(
            outcome: PreviousSessionOutcome.confirmedCrash,
            crashData: crashData,
          );
        }
      } catch (_) {}

      // 2. Check for confirmed Dart/Flutter fatal crash marker
      final crashFile = _getCrashMarkerFile(dir);
      if (crashFile.existsSync()) {
        try {
          final content = crashFile.readAsStringSync();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final crashData = ConfirmedCrashData.fromJson(json);

          // Clear crash marker so it is not processed repeatedly
          try {
            crashFile.deleteSync();
          } catch (_) {}

          return PreviousSessionEvaluation(
            outcome: PreviousSessionOutcome.confirmedCrash,
            crashData: crashData,
            previousSessionId: crashData.sessionId,
          );
        } catch (_) {
          try {
            crashFile.deleteSync();
          } catch (_) {}
        }
      }

      // 3. Inspect generic session lifecycle marker
      final lifecycleFile = _getLifecycleMarkerFile(dir);
      if (!lifecycleFile.existsSync()) {
        return const PreviousSessionEvaluation(
          outcome: PreviousSessionOutcome.firstRun,
        );
      }

      try {
        final content = lifecycleFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final state = json['state'] as String? ?? 'unknown';
        final prevSessionId = json['sessionId'] as String?;

        switch (state) {
          case 'clean_exit':
            return PreviousSessionEvaluation(
              outcome: PreviousSessionOutcome.cleanExit,
              previousSessionId: prevSessionId,
            );
          case 'background':
          case 'paused':
          case 'hidden':
            // Normal OS reclamation or user dismissed app from recents while backgrounded
            return PreviousSessionEvaluation(
              outcome: PreviousSessionOutcome.backgroundTerminated,
              previousSessionId: prevSessionId,
            );
          case 'foreground':
          default:
            // Unresolved termination (e.g. user swiped away from Recents or OS kill).
            // NOT a confirmed crash — must not be treated as a crash report.
            return PreviousSessionEvaluation(
              outcome: PreviousSessionOutcome.unresolvedTermination,
              previousSessionId: prevSessionId,
            );
        }
      } catch (_) {
        return const PreviousSessionEvaluation(
          outcome: PreviousSessionOutcome.unresolvedTermination,
        );
      }
    } catch (e) {
      debugPrint('[SessionMarkerManager] Evaluation error: $e');
      return const PreviousSessionEvaluation(
        outcome: PreviousSessionOutcome.firstRun,
      );
    }
  }

  /// Writes a confirmed fatal crash marker to disk.
  /// Called ONLY by unhandled error hooks when a fatal exception is verified.
  Future<void> recordConfirmedCrash({
    required String sessionId,
    required String errorType,
    required String exception,
    String? stackTrace,
  }) async {
    try {
      final dir = await _getDir();
      final crashFile = _getCrashMarkerFile(dir);
      final data = ConfirmedCrashData(
        sessionId: sessionId,
        timestamp: DateTime.now(),
        errorType: errorType,
        exception: exception,
        stackTrace: stackTrace,
      );
      crashFile.writeAsStringSync(jsonEncode(data.toJson()), flush: true);
    } catch (e) {
      debugPrint('[SessionMarkerManager] recordConfirmedCrash error: $e');
    }
  }

  /// Updates the lifecycle state of the current session.
  Future<void> updateLifecycleState({
    required String sessionId,
    required String state,
  }) async {
    try {
      final dir = await _getDir();
      final file = _getLifecycleMarkerFile(dir);
      final data = {
        'sessionId': sessionId,
        'state': state,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      file.writeAsStringSync(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  /// Clears any lingering confirmed crash marker.
  Future<void> clearConfirmedCrash() async {
    try {
      final dir = await _getDir();
      final crashFile = _getCrashMarkerFile(dir);
      if (crashFile.existsSync()) {
        crashFile.deleteSync();
      }
    } catch (_) {}
  }
}
