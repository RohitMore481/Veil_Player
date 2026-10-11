import 'package:veil_player/diagnostics/crash_handler.dart' as diag;

/// Legacy wrapper for CrashHandler.
/// Delegates directly to the isolated privacy-first diagnostics subsystem.
class CrashHandler {
  static String? currentScreen;
  static String? currentMediaFile;
  static String? currentDecoder;

  static void initialize() {
    diag.CrashHandler.initialize();
  }
}
