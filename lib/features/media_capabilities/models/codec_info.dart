/// Support level for a given codec or container.
enum SupportLevel {
  /// Fully supported — plays reliably on all target devices.
  full,

  /// Partially supported — may require software fallback or may lack HW decode.
  limited,

  /// Not supported — cannot be decoded.
  unsupported,
}

/// Describes a video codec known to the registry.
class VideoCodecInfo {
  /// Internal identifier matching mpv's `video-codec` property (e.g. `h264`, `hevc`).
  final String id;

  /// Human-readable display name (e.g. `H.264 / AVC`).
  final String displayName;

  /// Known support level within Veil's current runtime.
  final SupportLevel supportLevel;

  /// Whether hardware-accelerated decoding is commonly available for this codec.
  final bool hwDecodeAvailable;

  /// Optional notes shown in diagnostics (e.g. "Requires HEVC HW pack on some devices").
  final String? notes;

  const VideoCodecInfo({
    required this.id,
    required this.displayName,
    required this.supportLevel,
    this.hwDecodeAvailable = false,
    this.notes,
  });

  @override
  String toString() => 'VideoCodecInfo($id, $supportLevel)';
}

/// Describes an audio codec known to the registry.
class AudioCodecInfo {
  /// Internal identifier matching mpv's `audio-codec` property (e.g. `aac`, `ac3`).
  final String id;

  /// Human-readable display name (e.g. `AAC`, `Dolby TrueHD`).
  final String displayName;

  /// Known support level within Veil's current runtime.
  final SupportLevel supportLevel;

  /// Whether this codec supports lossless audio.
  final bool isLossless;

  /// Optional notes shown in diagnostics.
  final String? notes;

  const AudioCodecInfo({
    required this.id,
    required this.displayName,
    required this.supportLevel,
    this.isLossless = false,
    this.notes,
  });

  @override
  String toString() => 'AudioCodecInfo($id, $supportLevel)';
}

/// Describes a subtitle format known to the registry.
class SubtitleFormatInfo {
  /// Internal identifier (e.g. `srt`, `ass`, `pgs`).
  final String id;

  /// Human-readable display name (e.g. `SubRip (SRT)`, `PGS Blu-ray`).
  final String displayName;

  /// Known support level.
  final SupportLevel supportLevel;

  /// File extensions associated with this format.
  final List<String> extensions;

  /// Whether this is an image-based subtitle format (PGS, SUB/IDX).
  final bool isImageBased;

  const SubtitleFormatInfo({
    required this.id,
    required this.displayName,
    required this.supportLevel,
    required this.extensions,
    this.isImageBased = false,
  });

  @override
  String toString() => 'SubtitleFormatInfo($id, $supportLevel)';
}

/// Describes a media container format known to the registry.
class ContainerInfo {
  /// Internal identifier (e.g. `matroska`, `mp4`).
  final String id;

  /// Human-readable display name (e.g. `Matroska (MKV)`, `MPEG-4`).
  final String displayName;

  /// Known support level.
  final SupportLevel supportLevel;

  /// File extensions associated with this container.
  final List<String> extensions;

  const ContainerInfo({
    required this.id,
    required this.displayName,
    required this.supportLevel,
    required this.extensions,
  });

  @override
  String toString() => 'ContainerInfo($id, $supportLevel)';
}

/// A compatibility report for a specific file extension or codec query.
class CompatibilityReport {
  /// The queried extension or codec identifier.
  final String query;

  /// Overall support level.
  final SupportLevel supportLevel;

  /// Matched container info, if available.
  final ContainerInfo? container;

  /// Human-readable summary of compatibility status.
  final String message;

  const CompatibilityReport({
    required this.query,
    required this.supportLevel,
    this.container,
    required this.message,
  });

  bool get isSupported => supportLevel != SupportLevel.unsupported;
}
