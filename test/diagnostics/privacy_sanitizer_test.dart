import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/diagnostics/diagnostic_report.dart';
import 'package:veil_player/diagnostics/diagnostic_sanitizer.dart';
import 'package:veil_player/diagnostics/diagnostic_service.dart';

void main() {
  group('DiagnosticSanitizer Tests', () {
    test('Sanitizes Android external storage media paths', () {
      const input = 'Opening video at /storage/emulated/0/Movies/My Private Movie.mkv';
      final sanitized = DiagnosticSanitizer.sanitize(input);

      expect(sanitized, isNot(contains('/storage/emulated/0/Movies/My Private Movie.mkv')));
      expect(sanitized, isNot(contains('My Private Movie')));
      expect(sanitized, contains('<MEDIA_FILE.MKV>'));
    });

    test('Sanitizes WhatsApp media paths', () {
      const input = 'Media failed: /storage/emulated/0/WhatsApp/Media/WhatsApp Video/VID-2026.mp4';
      final sanitized = DiagnosticSanitizer.sanitize(input);

      expect(sanitized, isNot(contains('WhatsApp')));
      expect(sanitized, isNot(contains('VID-2026')));
      expect(sanitized, contains('<MEDIA_FILE.MP4>'));
    });

    test('Sanitizes Windows user paths', () {
      const input = r'Exception in C:\Users\Developer\Videos\private.mp4 at line 42';
      final sanitized = DiagnosticSanitizer.sanitize(input);

      expect(sanitized, isNot(contains(r'C:\Users\Developer')));
      expect(sanitized, isNot(contains('private.mp4')));
      expect(sanitized, contains(r'C:\Users\<USER>\'));
      expect(sanitized, contains('<MEDIA_FILE.MP4>'));
    });

    test('Sanitizes Android app internal data paths', () {
      const input = 'File error in /data/user/0/com.veil.player/cache/temp_sub.srt';
      final sanitized = DiagnosticSanitizer.sanitize(input);

      expect(sanitized, isNot(contains('/data/user/0/com.veil.player')));
      expect(sanitized, contains('<APP_PRIVATE_DIR>'));
    });

    test('Sanitizes stack traces while preserving Dart symbols', () {
      const stackTrace = '''
#0      PlayerScreen._exitPlayer (package:veil_player/features/player/screens/player_screen.dart:242:5)
#1      _invoke (C:\\Users\\Developer\\flutter\\packages\\flutter\\lib\\src\\gestures\\recognizer.dart:182:24)
#2      MediaKit.open (/storage/emulated/0/Download/SecretMovie.mkv)
''';

      final sanitized = DiagnosticSanitizer.sanitizeStackTrace(stackTrace);

      expect(sanitized, contains('PlayerScreen._exitPlayer'));
      expect(sanitized, contains('package:veil_player/features/player/screens/player_screen.dart:242:5'));
      expect(sanitized, isNot(contains(r'C:\Users\Developer')));
      expect(sanitized, isNot(contains('/storage/emulated/0/Download/SecretMovie.mkv')));
      expect(sanitized, isNot(contains('SecretMovie')));
    });

    test('Sanitizes IP addresses', () {
      const input = 'Failed stream connection to 192.168.1.105:8080';
      final sanitized = DiagnosticSanitizer.sanitize(input);

      expect(sanitized, isNot(contains('192.168.1.105')));
      expect(sanitized, contains('<IP_REDACTED>'));
    });

    test('Formats safe media metadata anonymously', () {
      final meta = DiagnosticSanitizer.formatSafeMediaMetadata(
        rawPath: '/storage/emulated/0/Movies/Vacation.mkv',
        duration: const Duration(hours: 1, minutes: 42, seconds: 31),
        width: 3840,
        height: 2160,
        videoCodec: 'HEVC',
        audioCodec: 'AAC',
        container: 'MKV',
        sessionAlias: 'MEDIA_1',
      );

      expect(meta['Media Identifier'], '<MEDIA_FILE> [MEDIA_1]');
      expect(meta['Container Format'], 'MKV');
      expect(meta['Resolution'], '3840x2160');
      expect(meta['Duration'], '01:42:31');
      expect(meta['Video Codec'], 'HEVC');
      expect(meta['Audio Codec'], 'AAC');
      expect(meta.values.join(' '), isNot(contains('Vacation')));
    });

    test('Sanitizes explicit PrivateTestMovie test paths (Android and Windows)', () {
      const androidPath = '/storage/emulated/0/Movies/PrivateTestMovie.mkv';
      const windowsPath = r'C:\Users\TestUser\Videos\PrivateTestMovie.mp4';
      const windowsForwardSlash = 'C:/Users/TestUser/Videos/PrivateTestMovie.mp4';

      final sanitizedAndroid = DiagnosticSanitizer.sanitize('Error playing $androidPath');
      final sanitizedWindows = DiagnosticSanitizer.sanitize('Error playing $windowsPath');
      final sanitizedWinForward = DiagnosticSanitizer.sanitize('Error playing $windowsForwardSlash');

      // Android verification
      expect(sanitizedAndroid, isNot(contains(androidPath)));
      expect(sanitizedAndroid, isNot(contains('PrivateTestMovie')));
      expect(sanitizedAndroid, isNot(contains('/storage/emulated/0/Movies/')));
      expect(sanitizedAndroid, contains('<MEDIA_FILE.MKV>'));

      // Windows verification (backslash)
      expect(sanitizedWindows, isNot(contains(windowsPath)));
      expect(sanitizedWindows, isNot(contains('PrivateTestMovie')));
      expect(sanitizedWindows, isNot(contains('TestUser')));
      expect(sanitizedWindows, contains(r'C:\Users\<USER>\'));
      expect(sanitizedWindows, contains('<MEDIA_FILE.MP4>'));

      // Windows verification (forward slash)
      expect(sanitizedWinForward, isNot(contains(windowsForwardSlash)));
      expect(sanitizedWinForward, isNot(contains('PrivateTestMovie')));
      expect(sanitizedWinForward, isNot(contains('TestUser')));
      expect(sanitizedWinForward, contains('C:/Users/<USER>/'));
      expect(sanitizedWinForward, contains('<MEDIA_FILE.MP4>'));
    });

    test('Sanitizes complex test stack trace with Dart symbols and private paths', () {
      const stackTrace = '''
#0      MediaCodecVideoRenderer.initDecoder (package:veil_player/player/media_codec.dart:184:14)
#1      PlaybackPipeline.prepareSource (package:veil_player/features/player/services/pipeline.dart:92:20)
#2      NativePlayerBridge.openMediaFile (C:\\Users\\TestUser\\Videos\\PrivateTestMovie.mp4:42:10)
#3      MediaKitController.load (/storage/emulated/0/Movies/PrivateTestMovie.mkv:15:3)
#4      _runMicrotasks (dart:async/schedule_microtask.dart:40:5)
''';

      final sanitized = DiagnosticSanitizer.sanitizeStackTrace(stackTrace);

      // Verify Dart technical symbols are preserved
      expect(sanitized, contains('MediaCodecVideoRenderer.initDecoder'));
      expect(sanitized, contains('package:veil_player/player/media_codec.dart:184:14'));
      expect(sanitized, contains('PlaybackPipeline.prepareSource'));
      expect(sanitized, contains('package:veil_player/features/player/services/pipeline.dart:92:20'));
      expect(sanitized, contains('NativePlayerBridge.openMediaFile'));
      expect(sanitized, contains('MediaKitController.load'));
      expect(sanitized, contains('_runMicrotasks'));

      // Verify private paths and usernames are completely redacted
      expect(sanitized, isNot(contains('PrivateTestMovie')));
      expect(sanitized, isNot(contains('TestUser')));
      expect(sanitized, isNot(contains('/storage/emulated/0/Movies/PrivateTestMovie.mkv')));
      expect(sanitized, isNot(contains(r'C:\Users\TestUser\Videos\PrivateTestMovie.mp4')));
      expect(sanitized, contains('<MEDIA_FILE.MP4>'));
      expect(sanitized, contains('<MEDIA_FILE.MKV>'));
    });

    test('Generates test playback-anomaly report through real pipeline without leaking private data', () async {
      final service = DiagnosticService.instance;
      final report = await service.createTestDiagnosticReport();

      expect(report, isNotNull);
      expect(report!.type, ReportType.testPlaybackAnomaly);
      expect(report.typeDisplayName, 'Test Playback Anomaly');
      expect(report.errorCategory, 'TEST_PLAYBACK_ANOMALY');

      final textReport = report.generateTextReport();

      // Ensure no private filenames or paths leak in the final formatted report
      expect(textReport, isNot(contains('PrivateTestMovie')));
      expect(textReport, isNot(contains('TestUser')));
      expect(textReport, isNot(contains('/storage/emulated/0/Movies/PrivateTestMovie.mkv')));
      expect(textReport, isNot(contains(r'C:\Users\TestUser\Videos\PrivateTestMovie.mp4')));

      // Ensure technical context is preserved
      expect(textReport, contains('SyntheticPlaybackException'));
      expect(textReport, contains('MediaCodecVideoRenderer'));
      expect(textReport, contains('Test Playback Anomaly'));
      expect(textReport, contains('<MEDIA_FILE.MKV>'));
      expect(textReport, contains('<MEDIA_FILE.MP4>'));
      expect(textReport, contains('Veil Player Version'));

      // Clean up test report from storage
      await service.deleteReport(report.id);
    });
  });
}
