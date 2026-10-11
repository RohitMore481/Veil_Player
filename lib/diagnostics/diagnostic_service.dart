import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diagnostic_event.dart';
import 'diagnostic_event_buffer.dart';
import 'diagnostic_report.dart';
import 'diagnostic_sanitizer.dart';
import 'diagnostic_storage.dart';
import 'responsiveness_monitor.dart';
import 'session_marker_manager.dart';

final diagnosticServiceProvider = Provider<DiagnosticService>((ref) {
  final service = DiagnosticService.instance;
  return service;
});

final diagnosticReportsProvider =
    FutureProvider.autoDispose<List<DiagnosticReport>>((ref) async {
  final service = ref.watch(diagnosticServiceProvider);
  return await service.loadReports();
});

final previousSessionStatusProvider = StateProvider<String?>((ref) => null);

/// Central Orchestrator for Veil Player's Privacy-First Diagnostics System.
class DiagnosticService with WidgetsBindingObserver {
  static final DiagnosticService instance = DiagnosticService._internal();

  final DiagnosticEventBuffer eventBuffer = DiagnosticEventBuffer(capacity: 150);
  final DiagnosticStorage storage = DiagnosticStorage();
  final SessionMarkerManager sessionMarkerManager = SessionMarkerManager();
  late final ResponsivenessMonitor responsivenessMonitor;

  static const _channel = MethodChannel('veil_player/media');

  final String sessionId = _generateAnonymousId();
  String? currentPlaybackSessionId;
  String currentAppState = 'Foreground';

  // Current playback context (sanitized)
  Map<String, String>? currentPlaybackContext;

  bool _initialized = false;
  bool _wasPreviousSessionConfirmedCrash = false;
  PreviousSessionOutcome? previousSessionOutcome;

  bool get wasPreviousSessionUnexpected => _wasPreviousSessionConfirmedCrash;
  bool get wasPreviousSessionConfirmedCrash => _wasPreviousSessionConfirmedCrash;

  DiagnosticService._internal() {
    responsivenessMonitor = ResponsivenessMonitor(
      onStallDetected: _onResponsivenessStall,
    );
  }

  /// Initializes diagnostic subsystem on app startup.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Register app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Record app launch event
    recordEvent(
      category: DiagnosticCategory.app,
      severity: DiagnosticSeverity.info,
      event: 'Application started',
      metadata: {'sessionId': sessionId},
    );

    // Start responsiveness monitor
    responsivenessMonitor.start();

    // Check previous session state using robust SessionMarkerManager
    await _checkPreviousSession();

    // Ensure session marker is registered for active session
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await sessionMarkerManager.updateLifecycleState(
        sessionId: sessionId,
        state: 'foreground',
      );
    });
  }

  /// Generate anonymous random ID (e.g. VP-9A8B7C6D)
  static String _generateAnonymousId() {
    final rnd = Random();
    final bytes = List<int>.generate(4, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return 'VP-$hex';
  }

  /// Start a new playback session for Video open
  String startPlaybackSession(String? videoId) {
    final newPlaybackId = _generateAnonymousId();
    currentPlaybackSessionId = newPlaybackId;
    recordEvent(
      category: DiagnosticCategory.player,
      severity: DiagnosticSeverity.info,
      event: 'Playback session started',
      playbackSessionId: newPlaybackId,
    );
    return newPlaybackId;
  }

  /// End active playback session
  void endPlaybackSession(String? playbackSessionId) {
    if (playbackSessionId == null || playbackSessionId == currentPlaybackSessionId) {
      recordEvent(
        category: DiagnosticCategory.player,
        severity: DiagnosticSeverity.info,
        event: 'Playback session ended',
        playbackSessionId: playbackSessionId ?? currentPlaybackSessionId,
      );
      if (playbackSessionId == currentPlaybackSessionId) {
        currentPlaybackSessionId = null;
        currentPlaybackContext = null;
      }
    }
  }

  /// Record a diagnostic event into the circular in-memory buffer.
  void recordEvent({
    required DiagnosticCategory category,
    required DiagnosticSeverity severity,
    required String event,
    Map<String, dynamic>? metadata,
    String? playbackSessionId,
  }) {
    try {
      final sanitizedEvent = DiagnosticSanitizer.sanitize(event);
      Map<String, dynamic>? sanitizedMeta;

      if (metadata != null) {
        sanitizedMeta = {};
        metadata.forEach((k, v) {
          sanitizedMeta![k] = v is String ? DiagnosticSanitizer.sanitize(v) : v;
        });
      }

      final diagEvent = DiagnosticEvent(
        timestamp: DateTime.now(),
        category: category,
        severity: severity,
        event: sanitizedEvent,
        metadata: sanitizedMeta,
        playbackSessionId: playbackSessionId ?? currentPlaybackSessionId,
      );

      eventBuffer.add(diagEvent);
    } catch (e) {
      // Fail silently - diagnostics must never crash Veil Player
    }
  }

  /// Callback when main thread stall is detected by [ResponsivenessMonitor].
  void _onResponsivenessStall({
    required Duration observedDelay,
    required String context,
  }) {
    recordEvent(
      category: DiagnosticCategory.system,
      severity: DiagnosticSeverity.warning,
      event: 'UI_RESPONSIVENESS_ANOMALY observed delay ~${observedDelay.inMilliseconds}ms during $context',
    );

    // Create anomaly report asynchronously if stall is severe (>3500ms)
    if (observedDelay.inMilliseconds >= 3500) {
      unawaited(createAnomalyReport(
        type: ReportType.uiResponsivenessAnomaly,
        category: 'SYSTEM',
        exceptionMessage: 'Main-isolate responsiveness stall observed (~${observedDelay.inMilliseconds} ms delay)',
        stackTrace: null,
      ));
    }
  }

  /// Create a Playback or Anomaly report safely.
  Future<DiagnosticReport?> createAnomalyReport({
    ReportType type = ReportType.playbackAnomaly,
    required String category,
    required String exceptionMessage,
    String? stackTrace,
    Map<String, String>? playbackInfo,
    String? playbackSessionId,
    Map<String, String>? extraSessionInfo,
  }) async {
    try {
      final reportId = _generateAnonymousId();
      final sanitizedException = DiagnosticSanitizer.sanitize(exceptionMessage);
      final sanitizedStack = stackTrace != null ? DiagnosticSanitizer.sanitizeStackTrace(stackTrace) : null;
      final deviceInfo = await _fetchDeviceInfo();
      final activePlaybackId = playbackSessionId ?? currentPlaybackSessionId;

      final report = DiagnosticReport(
        id: reportId,
        type: type,
        timestamp: DateTime.now(),
        appVersion: deviceInfo['app_version'] ?? '1.0.0',
        buildNumber: deviceInfo['build_number'] ?? '1',
        platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        deviceInfo: {
          'Manufacturer': deviceInfo['manufacturer'] ?? 'Unknown',
          'Model': deviceInfo['model'] ?? 'Unknown',
          'Android Version': deviceInfo['android_version'] ?? 'Unknown',
          'SDK Level': deviceInfo['sdk_int'] ?? 'Unknown',
          'Architecture': deviceInfo['arch'] ?? 'arm64-v8a',
        },
        sessionInfo: {
          'Session ID': sessionId,
          'Application State': currentAppState,
          'Player Active': activePlaybackId != null ? 'Yes' : 'No',
          'Playback Session ID': activePlaybackId ?? 'None',
          ...?extraSessionInfo,
        },
        playbackInfo: playbackInfo ?? currentPlaybackContext,
        errorCategory: category,
        exceptionMessage: sanitizedException,
        stackTrace: sanitizedStack,
        recentEvents: eventBuffer.getEvents(),
      );

      return await storage.saveReport(report);
    } catch (e) {
      debugPrint('[DiagnosticService] createAnomalyReport error: $e');
      return null;
    }
  }

  /// Generates a synthetic test diagnostic report for DEBUG testing.
  ///
  /// IMPORTANT:
  /// Available only in DEBUG builds (returns null in release mode).
  /// Reuses the production sanitization, event-buffer, and storage pipeline.
  /// Uses strictly synthetic data — never touches or exports real personal media filenames or paths.
  Future<DiagnosticReport?> createTestDiagnosticReport() async {
    if (!kDebugMode) {
      debugPrint('[DiagnosticService] createTestDiagnosticReport is unavailable in release mode.');
      return null;
    }

    try {
      final testPlaybackSessionId = 'VP-TEST-SESSION-${_generateAnonymousId().substring(3)}';

      // 1. Record synthetic recent events to test circular event buffer & sanitization
      recordEvent(
        category: DiagnosticCategory.player,
        severity: DiagnosticSeverity.info,
        event: 'Synthetic event: Test player session initiated for /storage/emulated/0/Movies/PrivateTestMovie.mkv',
        playbackSessionId: testPlaybackSessionId,
      );
      recordEvent(
        category: DiagnosticCategory.decoder,
        severity: DiagnosticSeverity.warning,
        event: 'Synthetic event: Hardware fallback triggered for C:\\Users\\TestUser\\Videos\\PrivateTestMovie.mp4',
        playbackSessionId: testPlaybackSessionId,
      );
      recordEvent(
        category: DiagnosticCategory.player,
        severity: DiagnosticSeverity.error,
        event: 'Synthetic event: Synthetic playback stall anomaly detected in media engine',
        playbackSessionId: testPlaybackSessionId,
      );

      // 2. Synthetic exception message with deliberately private-looking filenames
      const syntheticException =
          'SyntheticPlaybackException: MediaCodec decoder error [0xDEADBEEF] while parsing /storage/emulated/0/Movies/PrivateTestMovie.mkv (Windows fallback source: C:\\Users\\TestUser\\Videos\\PrivateTestMovie.mp4)';

      // 3. Synthetic stack trace with real Dart symbols and private paths
      const syntheticStackTrace = '''
#0      MediaCodecVideoRenderer.initDecoder (package:veil_player/player/media_codec.dart:184:14)
#1      PlaybackPipeline.prepareSource (package:veil_player/features/player/services/pipeline.dart:92:20)
#2      NativePlayerBridge.openMediaFile (C:\\Users\\TestUser\\Videos\\PrivateTestMovie.mp4:42:10)
#3      MediaKitController.load (/storage/emulated/0/Movies/PrivateTestMovie.mkv:15:3)
#4      _runMicrotasks (dart:async/schedule_microtask.dart:40:5)
''';

      // 4. Synthetic media metadata formatted through production sanitizer
      final testPlaybackMetadata = DiagnosticSanitizer.formatSafeMediaMetadata(
        rawPath: '/storage/emulated/0/Movies/PrivateTestMovie.mkv',
        duration: const Duration(hours: 1, minutes: 45, seconds: 12),
        width: 1920,
        height: 1080,
        videoCodec: 'H.264 / AVC (High@L4.1)',
        audioCodec: 'AAC-LC (Stereo, 48kHz)',
        container: 'MKV',
        hwDecoder: 'MediaCodec (c2.android.avc.decoder)',
        positionMs: 42000,
        speed: 1.0,
        sessionAlias: 'SYNTHETIC_TEST_SESSION',
      );
      testPlaybackMetadata['Test Source Context'] = DiagnosticSanitizer.sanitize(
        'Direct file input: /storage/emulated/0/Movies/PrivateTestMovie.mkv (Mirror: C:\\Users\\TestUser\\Videos\\PrivateTestMovie.mp4)',
      );

      // 5. Create and save the anomaly report through the real production pipeline
      return await createAnomalyReport(
        type: ReportType.testPlaybackAnomaly,
        category: 'TEST_PLAYBACK_ANOMALY',
        exceptionMessage: syntheticException,
        stackTrace: syntheticStackTrace,
        playbackInfo: testPlaybackMetadata,
        playbackSessionId: testPlaybackSessionId,
        extraSessionInfo: {
          'Test Mode': 'Synthetic Diagnostics Verification (DEBUG ONLY)',
          'Diagnostic Test ID': _generateAnonymousId(),
        },
      );
    } catch (e, stack) {
      debugPrint('[DiagnosticService] createTestDiagnosticReport error: $e\n$stack');
      return null;
    }
  }

  /// Create an uncaught Flutter or Dart crash report safely.
  Future<DiagnosticReport?> createCrashReport({
    required String exception,
    required StackTrace? stack,
    required String context,
  }) async {
    try {
      recordEvent(
        category: DiagnosticCategory.error,
        severity: DiagnosticSeverity.critical,
        event: 'Uncaught Exception in $context: $exception',
      );

      final reportId = _generateAnonymousId();
      final sanitizedException = DiagnosticSanitizer.sanitize(exception);
      final sanitizedStack = stack != null ? DiagnosticSanitizer.sanitizeStackTrace(stack.toString()) : null;
      final deviceInfo = await _fetchDeviceInfo();

      final report = DiagnosticReport(
        id: reportId,
        type: ReportType.applicationCrash,
        timestamp: DateTime.now(),
        appVersion: deviceInfo['app_version'] ?? '1.0.0',
        buildNumber: deviceInfo['build_number'] ?? '1',
        platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        deviceInfo: {
          'Manufacturer': deviceInfo['manufacturer'] ?? 'Unknown',
          'Model': deviceInfo['model'] ?? 'Unknown',
          'Android Version': deviceInfo['android_version'] ?? 'Unknown',
          'SDK Level': deviceInfo['sdk_int'] ?? 'Unknown',
          'Architecture': deviceInfo['arch'] ?? 'arm64-v8a',
        },
        sessionInfo: {
          'Session ID': sessionId,
          'Application State': currentAppState,
          'Context': context,
          'Player Active': currentPlaybackSessionId != null ? 'Yes' : 'No',
        },
        playbackInfo: currentPlaybackContext,
        errorCategory: 'UNCAUGHT_EXCEPTION',
        exceptionMessage: sanitizedException,
        stackTrace: sanitizedStack,
        recentEvents: eventBuffer.getEvents(),
      );

      return await storage.saveReport(report);
    } catch (e) {
      debugPrint('[DiagnosticService] createCrashReport error: $e');
      return null;
    }
  }

  /// Create a manual diagnostic report initiated by the user in Settings.
  Future<DiagnosticReport?> createManualReport({String? userNotes}) async {
    try {
      recordEvent(
        category: DiagnosticCategory.app,
        severity: DiagnosticSeverity.info,
        event: 'Manual diagnostic report requested by user',
      );

      final reportId = _generateAnonymousId();
      final deviceInfo = await _fetchDeviceInfo();

      final report = DiagnosticReport(
        id: reportId,
        type: ReportType.manualDiagnosticReport,
        timestamp: DateTime.now(),
        appVersion: deviceInfo['app_version'] ?? '1.0.0',
        buildNumber: deviceInfo['build_number'] ?? '1',
        platform: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        deviceInfo: {
          'Manufacturer': deviceInfo['manufacturer'] ?? 'Unknown',
          'Model': deviceInfo['model'] ?? 'Unknown',
          'Android Version': deviceInfo['android_version'] ?? 'Unknown',
          'SDK Level': deviceInfo['sdk_int'] ?? 'Unknown',
          'Architecture': deviceInfo['arch'] ?? 'arm64-v8a',
        },
        sessionInfo: {
          'Session ID': sessionId,
          'Application State': currentAppState,
          'Player Active': currentPlaybackSessionId != null ? 'Yes' : 'No',
        },
        playbackInfo: currentPlaybackContext,
        errorCategory: null,
        exceptionMessage: null,
        stackTrace: null,
        recentEvents: eventBuffer.getEvents(),
        userDescription: userNotes,
      );

      return await storage.saveReport(report);
    } catch (e) {
      debugPrint('[DiagnosticService] createManualReport error: $e');
      return null;
    }
  }

  /// Evaluates previous session using [SessionMarkerManager].
  /// Never misdiagnoses normal app backgrounding or recents swipe as a crash.
  Future<void> _checkPreviousSession() async {
    try {
      final evaluation = await sessionMarkerManager.evaluatePreviousSession();
      previousSessionOutcome = evaluation.outcome;

      if (evaluation.hasConfirmedCrash && evaluation.crashData != null) {
        _wasPreviousSessionConfirmedCrash = true;
        final crash = evaluation.crashData!;
        recordEvent(
          category: DiagnosticCategory.error,
          severity: DiagnosticSeverity.critical,
          event: 'Confirmed previous session fatal crash: ${crash.errorType} - ${crash.exception}',
        );

        // Record verified crash report
        unawaited(createCrashReport(
          exception: crash.exception,
          stack: crash.stackTrace != null
              ? StackTrace.fromString(crash.stackTrace!)
              : null,
          context: 'PreviousSession.${crash.errorType}',
        ));
      } else {
        _wasPreviousSessionConfirmedCrash = false;
        final outcomeMsg = switch (evaluation.outcome) {
          PreviousSessionOutcome.cleanExit => 'Previous session ended cleanly',
          PreviousSessionOutcome.backgroundTerminated =>
            'Previous session ended normally in background (OS reclamation / user task removal)',
          PreviousSessionOutcome.unresolvedTermination =>
            'Previous session ended normally (app closed / task removed)',
          _ => 'Initial application launch',
        };
        recordEvent(
          category: DiagnosticCategory.lifecycle,
          severity: DiagnosticSeverity.info,
          event: outcomeMsg,
        );
      }

      // Initialize lifecycle marker for this active session
      await sessionMarkerManager.updateLifecycleState(
        sessionId: sessionId,
        state: 'foreground',
      );
    } catch (e) {
      debugPrint('[DiagnosticService] _checkPreviousSession error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        currentAppState = 'Foreground';
        responsivenessMonitor.start();
        sessionMarkerManager.updateLifecycleState(
          sessionId: sessionId,
          state: 'foreground',
        );
        recordEvent(
          category: DiagnosticCategory.lifecycle,
          severity: DiagnosticSeverity.info,
          event: 'App resumed to foreground',
        );
        break;
      case AppLifecycleState.inactive:
        currentAppState = 'Inactive';
        sessionMarkerManager.updateLifecycleState(
          sessionId: sessionId,
          state: 'inactive',
        );
        recordEvent(
          category: DiagnosticCategory.lifecycle,
          severity: DiagnosticSeverity.info,
          event: 'App transitioned to inactive',
        );
        break;
      case AppLifecycleState.paused:
        currentAppState = 'Background';
        responsivenessMonitor.stop();
        sessionMarkerManager.updateLifecycleState(
          sessionId: sessionId,
          state: 'background',
        );
        recordEvent(
          category: DiagnosticCategory.lifecycle,
          severity: DiagnosticSeverity.info,
          event: 'App paused to background',
        );
        break;
      case AppLifecycleState.detached:
        currentAppState = 'Detached';
        responsivenessMonitor.stop();
        sessionMarkerManager.updateLifecycleState(
          sessionId: sessionId,
          state: 'clean_exit',
        );
        recordEvent(
          category: DiagnosticCategory.lifecycle,
          severity: DiagnosticSeverity.info,
          event: 'App detached / terminating',
        );
        break;
      case AppLifecycleState.hidden:
        currentAppState = 'Hidden';
        responsivenessMonitor.stop();
        sessionMarkerManager.updateLifecycleState(
          sessionId: sessionId,
          state: 'hidden',
        );
        break;
    }
  }

  /// Called on clean app shutdown or backgrounding.
  Future<void> onAppPausedOrClosed() async {
    responsivenessMonitor.stop();
    await sessionMarkerManager.updateLifecycleState(
      sessionId: sessionId,
      state: 'clean_exit',
    );
  }

  /// Dispose diagnostic service observer.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    responsivenessMonitor.stop();
  }

  /// Fetches safe, non-sensitive device info from native layer.
  Future<Map<String, String>> _fetchDeviceInfo() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getDeviceInfo');
      if (result != null) {
        return Map<String, String>.from(result.map((k, v) => MapEntry(k.toString(), v.toString())));
      }
    } catch (_) {}

    return {
      'manufacturer': 'Android Device',
      'model': 'Generic Model',
      'android_version': 'Android 14+',
      'sdk_int': '34',
      'arch': 'arm64-v8a',
      'app_version': '1.0.0',
      'build_number': '1',
    };
  }

  /// Loads all stored reports.
  Future<List<DiagnosticReport>> loadReports() async {
    return await storage.loadAllReports();
  }

  /// Deletes a report by ID.
  Future<bool> deleteReport(String id) async {
    return await storage.deleteReport(id);
  }

  /// Deletes all stored reports.
  Future<bool> deleteAllReports() async {
    return await storage.deleteAllReports();
  }

  /// Shares a report via native Android Share Sheet.
  Future<bool> shareReport(String reportId, {String? userDescription}) async {
    try {
      // If user notes were added, update the report file first
      if (userDescription != null && userDescription.trim().isNotEmpty) {
        final reports = await storage.loadAllReports();
        final match = reports.firstWhere((r) => r.id == reportId, orElse: () => reports.first);
        final updatedReport = DiagnosticReport(
          id: match.id,
          type: match.type,
          timestamp: match.timestamp,
          appVersion: match.appVersion,
          buildNumber: match.buildNumber,
          platform: match.platform,
          deviceInfo: match.deviceInfo,
          sessionInfo: match.sessionInfo,
          playbackInfo: match.playbackInfo,
          errorCategory: match.errorCategory,
          exceptionMessage: match.exceptionMessage,
          stackTrace: match.stackTrace,
          recentEvents: match.recentEvents,
          userDescription: userDescription,
          occurrenceCount: match.occurrenceCount,
        );
        await storage.saveReport(updatedReport);
      }

      final filePath = await storage.getReportFilePath(reportId);
      if (filePath == null) return false;

      final bool? result = await _channel.invokeMethod('shareReportFile', {
        'path': filePath,
        'title': 'Share Diagnostic Report',
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[DiagnosticService] shareReport error: $e');
      return false;
    }
  }
}
