import 'dart:async';
import 'package:flutter/foundation.dart';

import 'diagnostic_event.dart';
import 'diagnostic_service.dart';

/// Uncaught Flutter and Dart Asynchronous Crash Handler.
///
/// Hooks into Flutter framework error handling (`FlutterError.onError`) and Dart's
/// `PlatformDispatcher.instance.onError` to intercept unhandled exceptions.
///
/// Guarantees:
/// 1. Preserves default Flutter error presentation.
/// 2. Records sanitized error reports asynchronously in app-private storage.
/// 3. Never swallows errors or alters crash semantics.
/// 4. Never blocks the UI thread.
class CrashHandler {
  static bool _initialized = false;

  /// Registers global error hooks. Called once on app startup.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // 1. Flutter Framework error hook (e.g. build/rendering widget errors)
    FlutterError.onError = (FlutterErrorDetails details) {
      // Preserve standard Flutter debug/console error presentation
      FlutterError.presentError(details);

      final exceptionStr = details.exception.toString();
      final contextStr = details.context?.toString() ?? 'FlutterError';

      // Record event and write report asynchronously without awaiting
      DiagnosticService.instance.recordEvent(
        category: DiagnosticCategory.error,
        severity: DiagnosticSeverity.critical,
        event: 'Flutter framework error in $contextStr: $exceptionStr',
      );

      // Record confirmed crash marker synchronously/asynchronously
      unawaited(
        DiagnosticService.instance.sessionMarkerManager.recordConfirmedCrash(
          sessionId: DiagnosticService.instance.sessionId,
          errorType: 'FLUTTER_ERROR',
          exception: exceptionStr,
          stackTrace: details.stack?.toString(),
        ),
      );

      unawaited(
        DiagnosticService.instance.createCrashReport(
          exception: exceptionStr,
          stack: details.stack,
          context: contextStr,
        ),
      );
    };

    // 2. PlatformDispatcher asynchronous / zone error hook
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final exceptionStr = error.toString();
      const contextStr = 'PlatformDispatcher.onError';

      DiagnosticService.instance.recordEvent(
        category: DiagnosticCategory.error,
        severity: DiagnosticSeverity.critical,
        event: 'Async platform error: $exceptionStr',
      );

      unawaited(
        DiagnosticService.instance.sessionMarkerManager.recordConfirmedCrash(
          sessionId: DiagnosticService.instance.sessionId,
          errorType: 'DART_ASYNC_ERROR',
          exception: exceptionStr,
          stackTrace: stack.toString(),
        ),
      );

      unawaited(
        DiagnosticService.instance.createCrashReport(
          exception: exceptionStr,
          stack: stack,
          context: contextStr,
        ),
      );

      return true; // Marked as processed
    };
  }
}
