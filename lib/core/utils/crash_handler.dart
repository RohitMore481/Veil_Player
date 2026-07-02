import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Captures unhandled Flutter framework and PlatformDispatcher asynchronous errors.
///
/// Prepares context logs (current screen, media file, audio decoder) and calls
/// native method channels to save logs locally with device metadata.
class CrashHandler {
  static const _channel = MethodChannel('veil_player/media');

  // Diagnostic contextual fields updated dynamically by PlayerScreen
  static String? currentScreen;
  static String? currentMediaFile;
  static String? currentDecoder;

  /// Registers global error catch hooks. Called once on startup.
  static void initialize() {
    // Intercept Flutter framework rendering/rendering errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _reportError(
        exception: details.exception.toString(),
        stack: details.stack,
        context: 'FlutterError: ${details.context?.toString() ?? "unknown"}',
      );
    };

    // Intercept zone-based and asynchronous framework errors
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _reportError(
        exception: error.toString(),
        stack: stack,
        context: 'PlatformDispatcher.onError',
      );
      return true; // Mark as handled
    };
  }

  static Future<void> _reportError({
    required String exception,
    required StackTrace? stack,
    required String context,
  }) async {
    try {
      final logBuffer = StringBuffer();
      logBuffer.writeln('----------------------------------------');
      logBuffer.writeln('Context: $context');
      logBuffer.writeln('Exception: $exception');
      if (stack != null) {
        logBuffer.writeln('Stack Trace:');
        logBuffer.writeln(stack.toString());
      }
      logBuffer.writeln('Current Screen: ${currentScreen ?? "None"}');
      logBuffer.writeln('Current Media File: ${currentMediaFile ?? "None"}');
      logBuffer.writeln('Current Decoder: ${currentDecoder ?? "None"}');
      logBuffer.writeln('----------------------------------------');

      await _channel.invokeMethod('saveCrashLog', {
        'log': logBuffer.toString(),
      });
    } catch (e) {
      debugPrint('[CrashHandler] Failed to save crash log locally: $e');
    }
  }
}
