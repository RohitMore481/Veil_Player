import '../models/codec_info.dart';
import 'codec_registry.dart';

/// Answers compatibility queries about codecs, containers, and subtitle formats.
///
/// This is the primary API for "can Veil play this?" questions.
/// All lookups delegate to [CodecRegistry] — no hardcoded assumptions here.
class FormatSupportService {
  final CodecRegistry _registry;

  FormatSupportService({CodecRegistry? registry})
    : _registry = registry ?? CodecRegistry.instance;

  // ── Container queries ──────────────────────────────────────────────────────

  /// Whether a file extension is a known container (e.g. `mkv`, `mp4`).
  bool isKnownContainer(String extension) =>
      _registry.isKnownContainer(extension);

  /// Whether a file extension is supported (not marked unsupported).
  bool isContainerSupported(String extension) {
    final container = _registry.findContainer(extension);
    if (container == null) return false;
    return container.supportLevel != SupportLevel.unsupported;
  }

  /// The support level for a given file extension.
  SupportLevel containerSupportLevel(String extension) {
    return _registry.findContainer(extension)?.supportLevel ??
        SupportLevel.unsupported;
  }

  /// Full compatibility report for a file extension.
  CompatibilityReport getCompatibilityReport(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final container = _registry.findContainer(ext);

    if (container == null) {
      return CompatibilityReport(
        query: ext,
        supportLevel: SupportLevel.unsupported,
        message:
            'Unknown container format ".$ext". '
            'Veil may still attempt playback via mpv.',
      );
    }

    switch (container.supportLevel) {
      case SupportLevel.full:
        return CompatibilityReport(
          query: ext,
          supportLevel: SupportLevel.full,
          container: container,
          message: '${container.displayName} is fully supported.',
        );
      case SupportLevel.limited:
        return CompatibilityReport(
          query: ext,
          supportLevel: SupportLevel.limited,
          container: container,
          message:
              '${container.displayName} has limited support — '
              'some features may not work correctly.',
        );
      case SupportLevel.unsupported:
        return CompatibilityReport(
          query: ext,
          supportLevel: SupportLevel.unsupported,
          container: container,
          message: '${container.displayName} is not supported.',
        );
    }
  }

  // ── Video codec queries ────────────────────────────────────────────────────

  /// Whether a video codec id is supported (not marked unsupported).
  bool isVideoCodecSupported(String codecId) {
    final codec = _registry.findVideoCodec(codecId);
    if (codec == null) return true; // unknown → let mpv try
    return codec.supportLevel != SupportLevel.unsupported;
  }

  /// Support level for a video codec id.
  SupportLevel videoCodecSupportLevel(String codecId) {
    return _registry.findVideoCodec(codecId)?.supportLevel ?? SupportLevel.full;
  }

  /// Whether HW decode is available for a video codec.
  bool isHwDecodeAvailable(String codecId) {
    return _registry.findVideoCodec(codecId)?.hwDecodeAvailable ?? false;
  }

  // ── Audio codec queries ────────────────────────────────────────────────────

  /// Whether an audio codec id is supported.
  bool isAudioCodecSupported(String codecId) {
    final codec = _registry.findAudioCodec(codecId);
    if (codec == null) return true; // unknown → let mpv try
    return codec.supportLevel != SupportLevel.unsupported;
  }

  /// Support level for an audio codec id.
  SupportLevel audioCodecSupportLevel(String codecId) {
    return _registry.findAudioCodec(codecId)?.supportLevel ?? SupportLevel.full;
  }

  // ── Subtitle queries ───────────────────────────────────────────────────────

  /// Whether a file extension is a recognised subtitle format.
  bool isSubtitleExtensionSupported(String extension) {
    if (!_registry.isKnownSubtitleExtension(extension)) return false;
    final fmt = _registry.findSubtitleFormat(extension);
    return fmt != null && fmt.supportLevel != SupportLevel.unsupported;
  }

  // ── Display name resolution ────────────────────────────────────────────────

  /// Friendly display name for a video codec id (e.g. `h264` → `H.264 / AVC`).
  /// Returns the raw id if not in the registry.
  String videoCodecDisplayName(String codecId) {
    return _registry.findVideoCodec(codecId)?.displayName ??
        codecId.toUpperCase();
  }

  /// Friendly display name for an audio codec id (e.g. `ac3` → `Dolby Digital (AC3)`).
  /// Returns the raw id if not in the registry.
  String audioCodecDisplayName(String codecId) {
    return _registry.findAudioCodec(codecId)?.displayName ??
        codecId.toUpperCase();
  }

  /// Friendly display name for a container id or extension.
  String containerDisplayName(String idOrExtension) {
    return _registry.findContainer(idOrExtension)?.displayName ??
        idOrExtension.toUpperCase();
  }

  // ── Hardware decoder labels ────────────────────────────────────────────────

  /// Convert an mpv hardware decoder id to a friendly label.
  ///
  /// Examples:
  /// - `d3d11va`   → `DirectX 11 VA`
  /// - `nvdec`     → `NVIDIA NVDEC`
  /// - `vaapi`     → `VA-API`
  /// - `dxva2`     → `DirectX VA 2`
  /// - `videotoolbox` → `Apple VideoToolbox`
  /// - `mediacodec`   → `Android MediaCodec`
  String hwDecodeDisplayName(String hwDecodeRaw) {
    switch (hwDecodeRaw.toLowerCase()) {
      case 'd3d11va':
        return 'DirectX 11 VA';
      case 'd3d11va-copy':
        return 'DirectX 11 VA (copy)';
      case 'dxva2':
        return 'DirectX VA 2';
      case 'dxva2-copy':
        return 'DirectX VA 2 (copy)';
      case 'nvdec':
        return 'NVIDIA NVDEC';
      case 'nvdec-copy':
        return 'NVIDIA NVDEC (copy)';
      case 'cuda':
        return 'NVIDIA CUDA';
      case 'cuda-copy':
        return 'NVIDIA CUDA (copy)';
      case 'vaapi':
        return 'VA-API';
      case 'vaapi-copy':
        return 'VA-API (copy)';
      case 'vdpau':
        return 'VDPAU';
      case 'vdpau-copy':
        return 'VDPAU (copy)';
      case 'videotoolbox':
        return 'Apple VideoToolbox';
      case 'videotoolbox-copy':
        return 'Apple VideoToolbox (copy)';
      case 'mediacodec':
        return 'Android MediaCodec';
      case 'mediacodec-copy':
        return 'Android MediaCodec (copy)';
      case 'mmal':
        return 'Raspberry Pi MMAL';
      case 'drm-prime':
        return 'DRM-Prime';
      case 'auto':
        return 'Auto';
      case 'no':
      case 'none':
      case '':
        return 'Software';
      default:
        return hwDecodeRaw;
    }
  }
}
