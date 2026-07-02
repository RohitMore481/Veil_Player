import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Raw property bundle extracted from a live mpv [Player] instance.
///
/// All fields are nullable — the detector degrades gracefully when
/// properties are not available (e.g. stream not yet opened, platform
/// doesn't support a property).
class DetectedCodecProperties {
  final String? videoCodec;
  final String? audioCodec;
  final String? videoFormat;
  final String? audioFormat;
  final String? fileFormat;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? videoBitrate;
  final int? audioBitrate;
  final int? audioChannels;
  final int? audioSampleRate;
  final String? hwDecodeActive;
  final String? hwDecodeRequested;

  const DetectedCodecProperties({
    this.videoCodec,
    this.audioCodec,
    this.videoFormat,
    this.audioFormat,
    this.fileFormat,
    this.width,
    this.height,
    this.frameRate,
    this.videoBitrate,
    this.audioBitrate,
    this.audioChannels,
    this.audioSampleRate,
    this.hwDecodeActive,
    this.hwDecodeRequested,
  });

  /// Whether this bundle contains any meaningful data.
  bool get isEmpty =>
      videoCodec == null &&
      audioCodec == null &&
      fileFormat == null &&
      width == null &&
      height == null;

  @override
  String toString() =>
      'DetectedCodecProperties(video: $videoCodec, audio: $audioCodec, '
      '${width}x$height, container: $fileFormat, hwdec: $hwDecodeActive)';
}

/// Extracts live codec and playback properties from a running [media_kit] [Player].
///
/// All property reads are individually guarded by try/catch — a failure reading
/// one property never prevents the rest from being read.
///
/// This class never throws. On any error it logs via [debugPrint] and continues.
class CodecDetector {
  const CodecDetector();

  /// Detect all available properties from [player].
  ///
  /// Should be called after the player has opened and started playing a file
  /// (i.e. after the first `player.stream.tracks` or `player.stream.playing`
  /// event has fired) to maximise the number of populated fields.
  DetectedCodecProperties detect(Player player) {
    // We access mpv properties through the platform-specific interface.
    // This is intentionally cast via dynamic to avoid tight coupling to
    // the platform implementation class.
    final platform = _getPlatform(player);

    return DetectedCodecProperties(
      videoCodec: _readString(platform, 'video-codec'),
      audioCodec: _readString(platform, 'audio-codec'),
      videoFormat: _readString(platform, 'video-format'),
      audioFormat: _readString(platform, 'audio-format'),
      fileFormat: _readString(platform, 'file-format'),
      width: _readInt(platform, 'width') ?? player.state.width,
      height: _readInt(platform, 'height') ?? player.state.height,
      frameRate: _readDouble(platform, 'container-fps'),
      videoBitrate: _readInt(platform, 'video-bitrate'),
      audioBitrate: _readInt(platform, 'audio-bitrate'),
      audioChannels: _readInt(platform, 'audio-channels'),
      audioSampleRate: _readInt(platform, 'audio-samplerate'),
      hwDecodeActive: _readString(platform, 'hwdec-current'),
      hwDecodeRequested: _readString(platform, 'hwdec'),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  dynamic _getPlatform(Player player) {
    try {
      return player.platform;
    } catch (e) {
      debugPrint('[CodecDetector] Cannot access player platform: $e');
      return null;
    }
  }

  String? _readString(dynamic platform, String property) {
    if (platform == null) return null;
    try {
      final value = (platform as dynamic).getProperty(property) as String?;
      if (value == null ||
          value.isEmpty ||
          value == 'no' && property == 'hwdec-current') {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  int? _readInt(dynamic platform, String property) {
    if (platform == null) return null;
    try {
      final raw = (platform as dynamic).getProperty(property);
      if (raw == null) return null;
      if (raw is int) return raw;
      if (raw is double) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
      return null;
    } catch (_) {
      return null;
    }
  }

  double? _readDouble(dynamic platform, String property) {
    if (platform == null) return null;
    try {
      final raw = (platform as dynamic).getProperty(property);
      if (raw == null) return null;
      if (raw is double) return raw;
      if (raw is int) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    } catch (_) {
      return null;
    }
  }
}
