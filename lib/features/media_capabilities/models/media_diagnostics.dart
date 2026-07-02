import 'codec_info.dart';

/// A complete diagnostics snapshot for a media file captured from a live
/// [media_kit] Player session. All fields are nullable — the detector degrades
/// gracefully when properties are unavailable.
class MediaDiagnostics {
  // ── File identity ──────────────────────────────────────────────────────────
  final String? filePath;
  final int? fileSizeBytes;
  final Duration? duration;

  // ── Container ──────────────────────────────────────────────────────────────
  /// Raw container/format string as reported by mpv (e.g. `matroska,webm`).
  final String? containerRaw;

  /// Friendly container name resolved from the registry (e.g. `Matroska (MKV)`).
  final String? containerDisplayName;

  // ── Video track ────────────────────────────────────────────────────────────
  /// Raw video codec id as reported by mpv (e.g. `h264`, `hevc`).
  final String? videoCodecRaw;

  /// Friendly display name resolved from the registry (e.g. `H.264 / AVC`).
  final String? videoCodecDisplayName;

  /// Pixel format (e.g. `yuv420p`, `yuv420p10le`).
  final String? pixelFormat;

  /// Video width in pixels.
  final int? width;

  /// Video height in pixels.
  final int? height;

  /// Container frame rate (e.g. 23.976, 29.97, 60.0).
  final double? frameRate;

  /// Video bitrate in bits per second.
  final int? videoBitrate;

  // ── Audio track ────────────────────────────────────────────────────────────
  /// Raw audio codec id as reported by mpv (e.g. `aac`, `ac3`, `dts`).
  final String? audioCodecRaw;

  /// Friendly display name resolved from the registry (e.g. `Dolby Digital (AC3)`).
  final String? audioCodecDisplayName;

  /// Sample format (e.g. `fltp`, `s16`).
  final String? audioFormat;

  /// Number of audio channels (e.g. 2 for stereo, 6 for 5.1).
  final int? audioChannels;

  /// Audio sample rate in Hz (e.g. 48000).
  final int? audioSampleRate;

  /// Audio bitrate in bits per second.
  final int? audioBitrate;

  // ── Hardware decode ────────────────────────────────────────────────────────
  /// Whether a hardware decoder is actively in use.
  final bool hwDecodeActive;

  /// The active hardware decoder method (e.g. `d3d11va`, `nvdec`, `vaapi`).
  final String? hwDecodeMethod;

  /// Friendly label for the hardware decoder (e.g. `DirectX 11`, `NVIDIA NVDEC`).
  final String? hwDecodeDisplayName;

  // ── Subtitle tracks ────────────────────────────────────────────────────────
  /// Count of embedded subtitle tracks.
  final int embeddedSubtitleCount;

  /// Count of sidecar / external subtitle files discovered.
  final int externalSubtitleCount;

  // ── Support levels ─────────────────────────────────────────────────────────
  final SupportLevel videoSupportLevel;
  final SupportLevel audioSupportLevel;
  final SupportLevel containerSupportLevel;

  // ── Meta ───────────────────────────────────────────────────────────────────
  final DateTime analyzedAt;

  const MediaDiagnostics({
    this.filePath,
    this.fileSizeBytes,
    this.duration,
    this.containerRaw,
    this.containerDisplayName,
    this.videoCodecRaw,
    this.videoCodecDisplayName,
    this.pixelFormat,
    this.width,
    this.height,
    this.frameRate,
    this.videoBitrate,
    this.audioCodecRaw,
    this.audioCodecDisplayName,
    this.audioFormat,
    this.audioChannels,
    this.audioSampleRate,
    this.audioBitrate,
    this.hwDecodeActive = false,
    this.hwDecodeMethod,
    this.hwDecodeDisplayName,
    this.embeddedSubtitleCount = 0,
    this.externalSubtitleCount = 0,
    this.videoSupportLevel = SupportLevel.full,
    this.audioSupportLevel = SupportLevel.full,
    this.containerSupportLevel = SupportLevel.full,
    required this.analyzedAt,
  });

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// Total bitrate combining video and audio in kbps.
  int? get totalBitrateKbps {
    final v = videoBitrate;
    final a = audioBitrate;
    if (v == null && a == null) return null;
    return ((v ?? 0) + (a ?? 0)) ~/ 1000;
  }

  /// Human-readable resolution string (e.g. `1920×1080`).
  String? get resolutionString {
    if (width == null || height == null) return null;
    return '${width}x$height';
  }

  /// Resolution label (4K / 1080p / 720p / SD).
  String? get resolutionLabel {
    final h = height;
    if (h == null) return null;
    if (h >= 2160) return '4K UHD';
    if (h >= 1080) return '1080p Full HD';
    if (h >= 720) return '720p HD';
    if (h >= 480) return '480p SD';
    return 'SD';
  }

  /// Channel layout label (e.g. `Stereo`, `5.1 Surround`, `7.1 Surround`).
  String? get channelLayoutLabel {
    switch (audioChannels) {
      case 1:
        return 'Mono';
      case 2:
        return 'Stereo';
      case 6:
        return '5.1 Surround';
      case 8:
        return '7.1 Surround';
      default:
        if (audioChannels != null) return '$audioChannels ch';
        return null;
    }
  }

  /// Formatted frame rate string (e.g. `23.976 fps`).
  String? get frameRateString {
    if (frameRate == null) return null;
    return '${frameRate!.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} fps';
  }

  /// Formatted total bitrate string (e.g. `4,200 kbps`).
  String? get bitrateString {
    final kbps = totalBitrateKbps;
    if (kbps == null) return null;
    if (kbps >= 1000) {
      return '${(kbps / 1000.0).toStringAsFixed(1)} Mbps';
    }
    return '$kbps kbps';
  }

  /// Overall health: true if all supported tracks are within known-good levels.
  bool get isFullySupported =>
      videoSupportLevel == SupportLevel.full &&
      audioSupportLevel == SupportLevel.full &&
      containerSupportLevel == SupportLevel.full;

  MediaDiagnostics copyWith({
    String? filePath,
    int? fileSizeBytes,
    Duration? duration,
    String? containerRaw,
    String? containerDisplayName,
    String? videoCodecRaw,
    String? videoCodecDisplayName,
    String? pixelFormat,
    int? width,
    int? height,
    double? frameRate,
    int? videoBitrate,
    String? audioCodecRaw,
    String? audioCodecDisplayName,
    String? audioFormat,
    int? audioChannels,
    int? audioSampleRate,
    int? audioBitrate,
    bool? hwDecodeActive,
    String? hwDecodeMethod,
    String? hwDecodeDisplayName,
    int? embeddedSubtitleCount,
    int? externalSubtitleCount,
    SupportLevel? videoSupportLevel,
    SupportLevel? audioSupportLevel,
    SupportLevel? containerSupportLevel,
    DateTime? analyzedAt,
  }) {
    return MediaDiagnostics(
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      duration: duration ?? this.duration,
      containerRaw: containerRaw ?? this.containerRaw,
      containerDisplayName: containerDisplayName ?? this.containerDisplayName,
      videoCodecRaw: videoCodecRaw ?? this.videoCodecRaw,
      videoCodecDisplayName:
          videoCodecDisplayName ?? this.videoCodecDisplayName,
      pixelFormat: pixelFormat ?? this.pixelFormat,
      width: width ?? this.width,
      height: height ?? this.height,
      frameRate: frameRate ?? this.frameRate,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      audioCodecRaw: audioCodecRaw ?? this.audioCodecRaw,
      audioCodecDisplayName:
          audioCodecDisplayName ?? this.audioCodecDisplayName,
      audioFormat: audioFormat ?? this.audioFormat,
      audioChannels: audioChannels ?? this.audioChannels,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      hwDecodeActive: hwDecodeActive ?? this.hwDecodeActive,
      hwDecodeMethod: hwDecodeMethod ?? this.hwDecodeMethod,
      hwDecodeDisplayName: hwDecodeDisplayName ?? this.hwDecodeDisplayName,
      embeddedSubtitleCount:
          embeddedSubtitleCount ?? this.embeddedSubtitleCount,
      externalSubtitleCount:
          externalSubtitleCount ?? this.externalSubtitleCount,
      videoSupportLevel: videoSupportLevel ?? this.videoSupportLevel,
      audioSupportLevel: audioSupportLevel ?? this.audioSupportLevel,
      containerSupportLevel:
          containerSupportLevel ?? this.containerSupportLevel,
      analyzedAt: analyzedAt ?? this.analyzedAt,
    );
  }

  @override
  String toString() =>
      'MediaDiagnostics(video: $videoCodecRaw, audio: $audioCodecRaw, '
      'container: $containerRaw, ${width}x$height @ ${frameRateString ?? "?fps"})';
}
