import '../models/codec_info.dart';

/// Abstract base for a codec extension pack.
///
/// Future packs (e.g. AdvancedCodecPack, NetworkStreamingPack) implement this
/// interface and register via [CodecRegistry.instance.registerCodecPack].
/// The core player architecture never needs to change to add new format support.
abstract class CodecPack {
  /// Unique identifier for this pack (e.g. `advanced_codecs`, `network_streaming`).
  String get packId;

  /// Human-readable display name shown in diagnostics/settings.
  String get displayName;

  /// Additional video codecs provided by this pack.
  List<VideoCodecInfo> get videoCodecs => const [];

  /// Additional audio codecs provided by this pack.
  List<AudioCodecInfo> get audioCodecs => const [];

  /// Additional container formats provided by this pack.
  List<ContainerInfo> get containers => const [];

  /// Additional subtitle formats provided by this pack.
  List<SubtitleFormatInfo> get subtitleFormats => const [];
}

/// Central static registry of all known codecs, containers, and subtitle formats.
///
/// Design principles:
/// - Zero I/O — pure Dart, no platform calls, no file scanning.
/// - Lazy singleton — initialised once on first access.
/// - Extension-first — [registerCodecPack] allows future packs to add entries
///   without touching any core code.
/// - Normalised lookups — all identifiers are lowercased for reliable matching.
class CodecRegistry {
  CodecRegistry._();

  static CodecRegistry? _instance;

  /// Singleton accessor. Initialises the registry on first call.
  static CodecRegistry get instance {
    _instance ??= CodecRegistry._().._init();
    return _instance!;
  }

  // ── Internal storage ───────────────────────────────────────────────────────
  final Map<String, VideoCodecInfo> _videoCodecs = {};
  final Map<String, AudioCodecInfo> _audioCodecs = {};
  final Map<String, ContainerInfo> _containers = {};
  final Map<String, SubtitleFormatInfo> _subtitleFormats = {};

  /// Maps file extensions to container ids (e.g. `mkv` → `matroska`).
  final Map<String, String> _extensionToContainer = {};

  /// Maps subtitle file extensions to subtitle format ids (e.g. `srt` → `srt`).
  final Map<String, String> _extensionToSubtitle = {};

  /// Registered codec packs.
  final List<CodecPack> _registeredPacks = [];

  // ── Public read accessors ──────────────────────────────────────────────────

  /// All registered video codecs.
  List<VideoCodecInfo> get videoCodecs => _videoCodecs.values.toList();

  /// All registered audio codecs.
  List<AudioCodecInfo> get audioCodecs => _audioCodecs.values.toList();

  /// All registered containers.
  List<ContainerInfo> get containers => _containers.values.toList();

  /// All registered subtitle formats.
  List<SubtitleFormatInfo> get subtitleFormats =>
      _subtitleFormats.values.toList();

  /// All registered codec packs.
  List<CodecPack> get registeredPacks => List.unmodifiable(_registeredPacks);

  // ── Lookup API ─────────────────────────────────────────────────────────────

  /// Look up a video codec by its mpv identifier (case-insensitive).
  /// Returns null if unknown.
  VideoCodecInfo? findVideoCodec(String id) => _videoCodecs[id.toLowerCase()];

  /// Look up an audio codec by its mpv identifier (case-insensitive).
  /// Returns null if unknown.
  AudioCodecInfo? findAudioCodec(String id) => _audioCodecs[id.toLowerCase()];

  /// Look up a container by its mpv file-format string or extension.
  ContainerInfo? findContainer(String idOrExtension) {
    final key = idOrExtension.toLowerCase().replaceAll('.', '');
    // Try direct container id first
    if (_containers.containsKey(key)) return _containers[key];
    // Fall back to extension map
    final containerId = _extensionToContainer[key];
    if (containerId != null) return _containers[containerId];
    return null;
  }

  /// Look up a subtitle format by its id or file extension.
  SubtitleFormatInfo? findSubtitleFormat(String idOrExtension) {
    final key = idOrExtension.toLowerCase().replaceAll('.', '');
    if (_subtitleFormats.containsKey(key)) return _subtitleFormats[key];
    final fmtId = _extensionToSubtitle[key];
    if (fmtId != null) return _subtitleFormats[fmtId];
    return null;
  }

  /// Whether a file extension is a recognised media container.
  bool isKnownContainer(String extension) {
    final key = extension.toLowerCase().replaceAll('.', '');
    return _extensionToContainer.containsKey(key) ||
        _containers.containsKey(key);
  }

  /// Whether a file extension is a recognised subtitle format.
  bool isKnownSubtitleExtension(String extension) {
    final key = extension.toLowerCase().replaceAll('.', '');
    return _extensionToSubtitle.containsKey(key) ||
        _subtitleFormats.containsKey(key);
  }

  // ── Extension pack registration ────────────────────────────────────────────

  /// Register a [CodecPack] to extend the registry at runtime.
  ///
  /// Call this at app startup before any lookup. Future packs (Advanced Codec,
  /// Network Streaming, Experimental Decoder, etc.) use this entry point.
  ///
  /// Example:
  /// ```dart
  /// CodecRegistry.instance.registerCodecPack(AdvancedCodecPack());
  /// ```
  void registerCodecPack(CodecPack pack) {
    if (_registeredPacks.any((p) => p.packId == pack.packId)) return;
    _registeredPacks.add(pack);

    for (final v in pack.videoCodecs) {
      _videoCodecs[v.id.toLowerCase()] = v;
    }
    for (final a in pack.audioCodecs) {
      _audioCodecs[a.id.toLowerCase()] = a;
    }
    for (final c in pack.containers) {
      _containers[c.id.toLowerCase()] = c;
      for (final ext in c.extensions) {
        _extensionToContainer[ext.toLowerCase()] = c.id.toLowerCase();
      }
    }
    for (final s in pack.subtitleFormats) {
      _subtitleFormats[s.id.toLowerCase()] = s;
      for (final ext in s.extensions) {
        _extensionToSubtitle[ext.toLowerCase()] = s.id.toLowerCase();
      }
    }
  }

  // ── Private initialisation ─────────────────────────────────────────────────

  void _init() {
    _registerVideoCodecs();
    _registerAudioCodecs();
    _registerContainers();
    _registerSubtitleFormats();
  }

  void _registerVideoCodecs() {
    final codecs = <VideoCodecInfo>[
      // ── H.264 / AVC ────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'h264',
        displayName: 'H.264 / AVC',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),
      // mpv sometimes reports this variant
      const VideoCodecInfo(
        id: 'avc',
        displayName: 'H.264 / AVC',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),

      // ── H.265 / HEVC ────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'hevc',
        displayName: 'H.265 / HEVC',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),
      const VideoCodecInfo(
        id: 'h265',
        displayName: 'H.265 / HEVC',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),

      // ── AV1 ─────────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'av1',
        displayName: 'AV1',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
        notes: 'HW decode requires AV1-capable GPU (RTX 30xx, Intel Gen 11+)',
      ),
      const VideoCodecInfo(
        id: 'libaom-av1',
        displayName: 'AV1 (libaom)',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── VP9 ─────────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'vp9',
        displayName: 'VP9',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),
      const VideoCodecInfo(
        id: 'libvpx-vp9',
        displayName: 'VP9 (libvpx)',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── VP8 ─────────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'vp8',
        displayName: 'VP8',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),
      const VideoCodecInfo(
        id: 'libvpx',
        displayName: 'VP8 (libvpx)',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── MPEG-4 ──────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'mpeg4',
        displayName: 'MPEG-4 Part 2',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),
      const VideoCodecInfo(
        id: 'msmpeg4v3',
        displayName: 'MPEG-4 / DivX 3',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),
      const VideoCodecInfo(
        id: 'divx',
        displayName: 'DivX',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),
      const VideoCodecInfo(
        id: 'xvid',
        displayName: 'Xvid',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── MPEG-2 ──────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'mpeg2video',
        displayName: 'MPEG-2 Video',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),
      const VideoCodecInfo(
        id: 'mpeg2',
        displayName: 'MPEG-2 Video',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: true,
      ),

      // ── MPEG-1 ──────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'mpeg1video',
        displayName: 'MPEG-1 Video',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── Theora ──────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'theora',
        displayName: 'Theora',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── WMV ─────────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'wmv3',
        displayName: 'WMV3 / Windows Media Video 9',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),
      const VideoCodecInfo(
        id: 'wmv2',
        displayName: 'WMV2 / Windows Media Video 8',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),

      // ── H.263 ───────────────────────────────────────────────────────────────
      const VideoCodecInfo(
        id: 'h263',
        displayName: 'H.263',
        supportLevel: SupportLevel.full,
        hwDecodeAvailable: false,
      ),
    ];

    for (final c in codecs) {
      _videoCodecs[c.id.toLowerCase()] = c;
    }
  }

  void _registerAudioCodecs() {
    final codecs = <AudioCodecInfo>[
      // ── AAC ─────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'aac',
        displayName: 'AAC',
        supportLevel: SupportLevel.full,
      ),
      const AudioCodecInfo(
        id: 'aac_latm',
        displayName: 'AAC LATM',
        supportLevel: SupportLevel.full,
      ),

      // ── MP3 ─────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'mp3',
        displayName: 'MP3',
        supportLevel: SupportLevel.full,
      ),
      const AudioCodecInfo(
        id: 'mp3float',
        displayName: 'MP3',
        supportLevel: SupportLevel.full,
      ),

      // ── FLAC ────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'flac',
        displayName: 'FLAC',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),

      // ── Opus ────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'opus',
        displayName: 'Opus',
        supportLevel: SupportLevel.full,
      ),

      // ── Vorbis / OGG ────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'vorbis',
        displayName: 'Vorbis (OGG)',
        supportLevel: SupportLevel.full,
      ),

      // ── PCM / WAV variants ───────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'pcm_s16le',
        displayName: 'PCM 16-bit LE (WAV)',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),
      const AudioCodecInfo(
        id: 'pcm_s24le',
        displayName: 'PCM 24-bit LE (WAV)',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),
      const AudioCodecInfo(
        id: 'pcm_s32le',
        displayName: 'PCM 32-bit LE (WAV)',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),
      const AudioCodecInfo(
        id: 'pcm_f32le',
        displayName: 'PCM Float 32-bit LE (WAV)',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),
      const AudioCodecInfo(
        id: 'pcm_s16be',
        displayName: 'PCM 16-bit BE',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),

      // ── AC3 / Dolby Digital ─────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'ac3',
        displayName: 'Dolby Digital (AC3)',
        supportLevel: SupportLevel.full,
      ),

      // ── EAC3 / Dolby Digital Plus ────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'eac3',
        displayName: 'Dolby Digital Plus (EAC3)',
        supportLevel: SupportLevel.full,
      ),

      // ── DTS ─────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'dts',
        displayName: 'DTS',
        supportLevel: SupportLevel.full,
      ),

      // ── DTS-HD ──────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'dts-hd',
        displayName: 'DTS-HD Master Audio',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),
      // mpv may also report this with underscore
      const AudioCodecInfo(
        id: 'dts_hd',
        displayName: 'DTS-HD Master Audio',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),

      // ── TrueHD / Dolby Atmos ────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'truehd',
        displayName: 'Dolby TrueHD / Atmos',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),

      // ── ALAC ────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'alac',
        displayName: 'Apple Lossless (ALAC)',
        supportLevel: SupportLevel.full,
        isLossless: true,
      ),

      // ── WMA ─────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'wmav2',
        displayName: 'Windows Media Audio (WMA)',
        supportLevel: SupportLevel.full,
      ),
      const AudioCodecInfo(
        id: 'wmapro',
        displayName: 'WMA Pro',
        supportLevel: SupportLevel.full,
      ),

      // ── MP2 ─────────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'mp2',
        displayName: 'MPEG Audio Layer 2 (MP2)',
        supportLevel: SupportLevel.full,
      ),

      // ── Speex ───────────────────────────────────────────────────────────────
      const AudioCodecInfo(
        id: 'speex',
        displayName: 'Speex',
        supportLevel: SupportLevel.full,
      ),
    ];

    for (final c in codecs) {
      _audioCodecs[c.id.toLowerCase()] = c;
    }
  }

  void _registerContainers() {
    final containers = <ContainerInfo>[
      const ContainerInfo(
        id: 'matroska',
        displayName: 'Matroska (MKV)',
        supportLevel: SupportLevel.full,
        extensions: ['mkv', 'mka', 'mks', 'mk3d'],
      ),
      const ContainerInfo(
        id: 'mp4',
        displayName: 'MPEG-4 (MP4)',
        supportLevel: SupportLevel.full,
        extensions: ['mp4', 'm4v', 'm4a', 'm4b'],
      ),
      const ContainerInfo(
        id: 'avi',
        displayName: 'AVI',
        supportLevel: SupportLevel.full,
        extensions: ['avi'],
      ),
      const ContainerInfo(
        id: 'mov',
        displayName: 'QuickTime (MOV)',
        supportLevel: SupportLevel.full,
        extensions: ['mov', 'qt'],
      ),
      const ContainerInfo(
        id: 'webm',
        displayName: 'WebM',
        supportLevel: SupportLevel.full,
        extensions: ['webm'],
      ),
      const ContainerInfo(
        id: 'mpegts',
        displayName: 'MPEG-TS',
        supportLevel: SupportLevel.full,
        extensions: ['ts', 'mts', 'm2ts', 'trp'],
      ),
      // mpv also reports this as 'mpegts' but extension can vary
      const ContainerInfo(
        id: 'mts',
        displayName: 'AVCHD (MTS)',
        supportLevel: SupportLevel.full,
        extensions: ['mts'],
      ),
      const ContainerInfo(
        id: 'flv',
        displayName: 'Flash Video (FLV)',
        supportLevel: SupportLevel.full,
        extensions: ['flv', 'f4v'],
      ),
      const ContainerInfo(
        id: '3gp',
        displayName: '3GPP',
        supportLevel: SupportLevel.full,
        extensions: ['3gp', '3g2', '3gpp'],
      ),
      const ContainerInfo(
        id: 'ogg',
        displayName: 'OGG',
        supportLevel: SupportLevel.full,
        extensions: ['ogg', 'ogv', 'oga', 'ogx'],
      ),
      const ContainerInfo(
        id: 'asf',
        displayName: 'ASF / WMV',
        supportLevel: SupportLevel.full,
        extensions: ['asf', 'wmv', 'wma'],
      ),
      const ContainerInfo(
        id: 'rm',
        displayName: 'RealMedia',
        supportLevel: SupportLevel.limited,
        extensions: ['rm', 'rmvb', 'ra'],
      ),
      const ContainerInfo(
        id: 'mpeg',
        displayName: 'MPEG Program Stream',
        supportLevel: SupportLevel.full,
        extensions: ['mpeg', 'mpg', 'mpe', 'vob'],
      ),
      const ContainerInfo(
        id: 'wav',
        displayName: 'WAV',
        supportLevel: SupportLevel.full,
        extensions: ['wav'],
      ),
      const ContainerInfo(
        id: 'flac',
        displayName: 'FLAC Audio',
        supportLevel: SupportLevel.full,
        extensions: ['flac'],
      ),
      const ContainerInfo(
        id: 'mp3',
        displayName: 'MP3 Audio',
        supportLevel: SupportLevel.full,
        extensions: ['mp3'],
      ),
    ];

    for (final c in containers) {
      _containers[c.id.toLowerCase()] = c;
      for (final ext in c.extensions) {
        _extensionToContainer[ext.toLowerCase()] = c.id.toLowerCase();
      }
    }
  }

  void _registerSubtitleFormats() {
    final formats = <SubtitleFormatInfo>[
      const SubtitleFormatInfo(
        id: 'srt',
        displayName: 'SubRip (SRT)',
        supportLevel: SupportLevel.full,
        extensions: ['srt'],
      ),
      const SubtitleFormatInfo(
        id: 'ass',
        displayName: 'Advanced SubStation Alpha (ASS)',
        supportLevel: SupportLevel.full,
        extensions: ['ass'],
      ),
      const SubtitleFormatInfo(
        id: 'ssa',
        displayName: 'SubStation Alpha (SSA)',
        supportLevel: SupportLevel.full,
        extensions: ['ssa'],
      ),
      const SubtitleFormatInfo(
        id: 'vtt',
        displayName: 'WebVTT',
        supportLevel: SupportLevel.full,
        extensions: ['vtt'],
      ),
      const SubtitleFormatInfo(
        id: 'pgs',
        displayName: 'PGS (Blu-ray)',
        supportLevel: SupportLevel.full,
        extensions: ['sup'],
        isImageBased: true,
      ),
      const SubtitleFormatInfo(
        id: 'sub',
        displayName: 'MicroDVD / VobSub (SUB)',
        supportLevel: SupportLevel.full,
        extensions: ['sub'],
        isImageBased: false,
      ),
      const SubtitleFormatInfo(
        id: 'idx',
        displayName: 'VobSub Index (IDX)',
        supportLevel: SupportLevel.full,
        extensions: ['idx'],
        isImageBased: true,
      ),
      const SubtitleFormatInfo(
        id: 'smi',
        displayName: 'SAMI',
        supportLevel: SupportLevel.limited,
        extensions: ['smi', 'sami'],
      ),
      const SubtitleFormatInfo(
        id: 'lrc',
        displayName: 'LRC Lyrics',
        supportLevel: SupportLevel.limited,
        extensions: ['lrc'],
      ),
    ];

    for (final f in formats) {
      _subtitleFormats[f.id.toLowerCase()] = f;
      for (final ext in f.extensions) {
        _extensionToSubtitle[ext.toLowerCase()] = f.id.toLowerCase();
      }
    }
  }
}
