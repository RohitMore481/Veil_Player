import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/codec_info.dart';
import '../models/media_diagnostics.dart';
import '../models/playback_error.dart';
import '../registry/format_support_service.dart';
import 'codec_detector.dart';

/// Orchestrates a full diagnostics analysis for a currently-open media file.
///
/// Responsibilities:
/// 1. Delegates property extraction to [CodecDetector].
/// 2. Resolves display names and support levels via [FormatSupportService].
/// 3. Returns a complete [MediaDiagnostics] snapshot.
/// 4. Classifies playback errors into [PlaybackError] when failures occur.
///
/// This service is **lazy** — it only runs when explicitly called.
/// It never polls, scans, or pre-reads files.
class MediaDiagnosticsService {
  final CodecDetector _detector;
  final FormatSupportService _supportService;

  MediaDiagnosticsService({
    CodecDetector? detector,
    FormatSupportService? supportService,
  }) : _detector = detector ?? const CodecDetector(),
       _supportService = supportService ?? FormatSupportService();

  // ── Primary API ────────────────────────────────────────────────────────────

  /// Perform a full diagnostics analysis on [player].
  ///
  /// [filePath]        — path of the currently playing file (optional but recommended).
  /// [fileSizeBytes]   — file size in bytes (from VideoItem.size).
  /// [duration]        — total playback duration.
  /// [embeddedSubtitleCount] — number of embedded subtitle tracks.
  /// [externalSubtitleCount] — number of sidecar subtitle files discovered.
  ///
  /// Returns a [MediaDiagnostics] snapshot. Never throws.
  Future<MediaDiagnostics> analyze({
    required Player player,
    String? filePath,
    int? fileSizeBytes,
    Duration? duration,
    int embeddedSubtitleCount = 0,
    int externalSubtitleCount = 0,
  }) async {
    try {
      // Detect live properties from the mpv player
      final props = _detector.detect(player);

      debugPrint('[MediaDiagnosticsService] Detected: $props');

      // Resolve video codec
      final videoCodecRaw = _normaliseCodecId(props.videoCodec);
      final videoDisplayName = videoCodecRaw != null
          ? _supportService.videoCodecDisplayName(videoCodecRaw)
          : null;
      final videoSupport = videoCodecRaw != null
          ? _supportService.videoCodecSupportLevel(videoCodecRaw)
          : SupportLevel.full;

      // Resolve audio codec
      final audioCodecRaw = _normaliseCodecId(props.audioCodec);
      final audioDisplayName = audioCodecRaw != null
          ? _supportService.audioCodecDisplayName(audioCodecRaw)
          : null;
      final audioSupport = audioCodecRaw != null
          ? _supportService.audioCodecSupportLevel(audioCodecRaw)
          : SupportLevel.full;

      // Resolve container
      final containerRaw = _normaliseContainerId(props.fileFormat);
      final containerDisplayName = containerRaw != null
          ? _supportService.containerDisplayName(containerRaw)
          : _inferContainerFromPath(filePath);
      final containerSupportStr = containerRaw != null
          ? _supportService.containerSupportLevel(containerRaw)
          : SupportLevel.full;

      // Resolve HW decoder
      final hwRaw = props.hwDecodeActive;
      final hwActive =
          hwRaw != null && hwRaw.isNotEmpty && hwRaw != 'no' && hwRaw != 'none';
      final hwDisplayName = hwRaw != null && hwRaw.isNotEmpty && hwRaw != 'no'
          ? _supportService.hwDecodeDisplayName(hwRaw)
          : null;

      return MediaDiagnostics(
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        duration: duration,
        containerRaw: containerRaw,
        containerDisplayName: containerDisplayName,
        videoCodecRaw: videoCodecRaw,
        videoCodecDisplayName: videoDisplayName,
        pixelFormat: props.videoFormat,
        width: props.width,
        height: props.height,
        frameRate: props.frameRate,
        videoBitrate: props.videoBitrate,
        audioCodecRaw: audioCodecRaw,
        audioCodecDisplayName: audioDisplayName,
        audioFormat: props.audioFormat,
        audioChannels: props.audioChannels,
        audioSampleRate: props.audioSampleRate,
        audioBitrate: props.audioBitrate,
        hwDecodeActive: hwActive,
        hwDecodeMethod: hwRaw,
        hwDecodeDisplayName: hwDisplayName,
        embeddedSubtitleCount: embeddedSubtitleCount,
        externalSubtitleCount: externalSubtitleCount,
        videoSupportLevel: videoSupport,
        audioSupportLevel: audioSupport,
        containerSupportLevel: containerSupportStr,
        analyzedAt: DateTime.now(),
      );
    } catch (e, stack) {
      debugPrint('[MediaDiagnosticsService] analyze() error: $e\n$stack');
      // Return a minimal valid diagnostics rather than propagating
      return MediaDiagnostics(
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        duration: duration,
        analyzedAt: DateTime.now(),
      );
    }
  }

  /// Classify a playback error from the current player state.
  ///
  /// Returns null if no error is detected (playback is healthy).
  PlaybackError? classifyError(Player player) {
    try {
      // Errors in media_kit are typically emitted via player.stream.error.
      // Since player.state doesn't hold the last error, we rely on the stream listener
      // in PlayerScreen to capture errors and use classifyRawError() instead.
      return null;
    } catch (e) {
      debugPrint('[MediaDiagnosticsService] classifyError() error: $e');
      return null;
    }
  }

  /// Classify a raw error string into a [PlaybackError].
  /// Useful for classifying errors received via streams.
  PlaybackError classifyRawError(String errorMessage) {
    final kind = _classifyErrorMessage(errorMessage);
    final codecOrContainer = _extractCodecFromError(errorMessage);
    return PlaybackError(
      kind: kind,
      rawMessage: errorMessage,
      codecOrContainer: codecOrContainer,
      detectedAt: DateTime.now(),
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Normalise a raw mpv codec string for registry lookup.
  String? _normaliseCodecId(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'none') return null;
    // mpv sometimes reports "mpeg4 (Simple@L3)" — strip the parens
    final clean = raw.split('(').first.trim().toLowerCase();
    return clean.isEmpty ? null : clean;
  }

  /// Normalise a raw mpv file-format string.
  /// mpv often returns comma-separated values like `matroska,webm` — use the first.
  String? _normaliseContainerId(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'none') return null;
    return raw.split(',').first.trim().toLowerCase();
  }

  /// Infer a container display name from the file extension if mpv didn't report one.
  String? _inferContainerFromPath(String? path) {
    if (path == null) return null;
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    return _supportService.containerDisplayName(ext);
  }

  PlaybackErrorKind _classifyErrorMessage(String msg) {
    final lower = msg.toLowerCase();

    // Corruption / truncation patterns
    if (lower.contains('corrupt') ||
        lower.contains('invalid data') ||
        lower.contains('moov atom not found') ||
        lower.contains('end of file') ||
        lower.contains('truncated')) {
      return PlaybackErrorKind.corruptedFile;
    }

    // Network errors
    if (lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('http') ||
        lower.contains('timeout') ||
        lower.contains('refused') ||
        lower.contains('unreachable')) {
      return PlaybackErrorKind.networkError;
    }

    // Container / demux errors
    if (lower.contains('no such file') ||
        lower.contains('demux') ||
        lower.contains('container') ||
        lower.contains('format not supported') ||
        lower.contains('unknown format') ||
        lower.contains('unable to determine file format')) {
      return PlaybackErrorKind.containerError;
    }

    // Missing track patterns
    if (lower.contains('no video') ||
        lower.contains('no audio') ||
        lower.contains('no track') ||
        lower.contains('missing track') ||
        lower.contains('stream not found')) {
      return PlaybackErrorKind.missingTrack;
    }

    // Video codec errors
    if (lower.contains('video decoder') ||
        lower.contains('video codec') ||
        lower.contains('could not open video') ||
        lower.contains('vdec') ||
        lower.contains('failed to init video')) {
      return PlaybackErrorKind.unsupportedVideoCodec;
    }

    // Audio codec errors
    if (lower.contains('audio decoder') ||
        lower.contains('audio codec') ||
        lower.contains('could not open audio') ||
        lower.contains('adec') ||
        lower.contains('failed to init audio')) {
      return PlaybackErrorKind.unsupportedAudioCodec;
    }

    return PlaybackErrorKind.unknown;
  }

  /// Attempt to extract a codec or container name from an error message.
  String? _extractCodecFromError(String msg) {
    // Try to find a codec name in common error patterns like:
    // "Video codec h265 could not be initialized"
    final patterns = [
      RegExp(r'codec[:\s]+(\w+)', caseSensitive: false),
      RegExp(r'decoder[:\s]+(\w+)', caseSensitive: false),
      RegExp(r'format[:\s]+(\w+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(msg);
      if (match != null) {
        final candidate = match.group(1);
        if (candidate != null &&
            candidate.length > 2 &&
            candidate.toLowerCase() != 'not' &&
            candidate.toLowerCase() != 'the') {
          return candidate;
        }
      }
    }
    return null;
  }
}
