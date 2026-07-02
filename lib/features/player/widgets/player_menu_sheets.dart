import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/widgets/veil_bottom_sheet.dart';
import '../models/subtitle_settings.dart';
import '../../media_capabilities/models/media_diagnostics.dart';
import '../../media_capabilities/models/codec_info.dart';

class PlayerMenuSheets {
  static void showSubtitleSettings({
    required BuildContext context,
    required SubtitleSettings settings,
    required List<SubtitleTrack> tracks,
    required SubtitleTrack activeTrack,
    required int currentDelayMs,
    required ValueChanged<SubtitleSettings> onChanged,
    required ValueChanged<SubtitleTrack> onTrackSelected,
    required ValueChanged<int> onDelayChanged,
    required VoidCallback onAddExternal,
  }) {
    SubtitleTrack currentActiveTrack = activeTrack;
    int currentActiveDelayMs = currentDelayMs;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      elevation: 0,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);

            // Categorize tracks
            final List<SubtitleTrack> embeddedTracks = [];
            final List<SubtitleTrack> externalTracks = [];

            for (final track in tracks) {
              if (track.id == 'no' || track.id == 'auto') continue;

              final titleLower = (track.title ?? '').toLowerCase();
              final isExternal =
                  track.id.startsWith('/') ||
                  track.id.startsWith('file://') ||
                  track.id.startsWith('content://') ||
                  titleLower.contains('external') ||
                  titleLower.contains('cache') ||
                  track.id.contains('picked_subtitles');
              if (isExternal) {
                externalTracks.add(track);
              } else {
                embeddedTracks.add(track);
              }
            }

            return VeilBottomSheet(
              title: 'Subtitles',
              subtitle: 'Select subtitle track',
              children: [
                // Subtitle Delay Adjuster
                _buildSyncOffsetAdjuster(
                  theme: theme,
                  title: 'Subtitle Sync Offset',
                  currentValueMs: currentActiveDelayMs,
                  onChanged: (newVal) {
                    onDelayChanged(newVal);
                    setModalState(() {
                      currentActiveDelayMs = newVal;
                    });
                  },
                ),
                const Divider(height: 1),

                // TRACK SELECTION
                _buildHeader(theme, 'TRACK SELECTION'),

                // Track: Off
                _buildTrackTile(
                  theme: theme,
                  title: 'Off',
                  isSelected: currentActiveTrack.id == 'no',
                  onTap: () {
                    final offTrack = tracks.firstWhere(
                      (t) => t.id == 'no',
                      orElse: () => SubtitleTrack.no(),
                    );
                    onTrackSelected(offTrack);
                    onChanged(settings.copyWith(enabled: false));
                    setModalState(() {
                      currentActiveTrack = offTrack;
                    });
                  },
                ),

                // External Subtitles Section
                if (externalTracks.isNotEmpty) ...[
                  _buildSubHeader(theme, 'External Subtitles'),
                  ...externalTracks.map((track) {
                    final title = track.title != null && track.title!.isNotEmpty
                        ? track.title!
                        : 'External Track';
                    final isSelected = currentActiveTrack.id == track.id;
                    return _buildTrackTile(
                      theme: theme,
                      title: title,
                      isSelected: isSelected,
                      onTap: () {
                        onTrackSelected(track);
                        onChanged(settings.copyWith(enabled: true));
                        setModalState(() {
                          currentActiveTrack = track;
                        });
                      },
                    );
                  }),
                ],

                // Embedded Subtitles Section
                if (embeddedTracks.isNotEmpty) ...[
                  _buildSubHeader(theme, 'Embedded Subtitles'),
                  ...embeddedTracks.map((track) {
                    final title = track.title != null && track.title!.isNotEmpty
                        ? track.title!
                        : 'Track ${track.id}';
                    final lang =
                        track.language != null && track.language!.isNotEmpty
                        ? ' [${track.language!.toUpperCase()}]'
                        : '';
                    final isSelected = currentActiveTrack.id == track.id;
                    return _buildTrackTile(
                      theme: theme,
                      title: '$title$lang',
                      isSelected: isSelected,
                      onTap: () {
                        onTrackSelected(track);
                        onChanged(settings.copyWith(enabled: true));
                        setModalState(() {
                          currentActiveTrack = track;
                        });
                      },
                    );
                  }),
                ],

                const SizedBox(height: 16),
                Center(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    icon: Icon(
                      Icons.folder_open_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    label: Text(
                      '📂 Browse Device',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context); // close sheet first
                      onAddExternal();
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _buildHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 12.0, bottom: 8.0),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  static Widget _buildSubHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 4.0),
      child: Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static Widget _buildTrackTile({
    required ThemeData theme,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected
              ? const Color(0xFF10B981)
              : theme.colorScheme.onSurface,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: Color(0xFF10B981), size: 18)
          : null,
      onTap: onTap,
    );
  }

  static void showAudioTrackSettings({
    required BuildContext context,
    required List<AudioTrack> tracks,
    required AudioTrack selectedTrack,
    required int currentDelayMs,
    required ValueChanged<AudioTrack> onSelected,
    required ValueChanged<int> onDelayChanged,
  }) {
    int currentActiveDelayMs = currentDelayMs;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      elevation: 0,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);

            return VeilBottomSheet(
              title: 'Audio Tracks',
              subtitle: 'Select audio channel stream',
              children: [
                // Audio Delay Adjuster
                _buildSyncOffsetAdjuster(
                  theme: theme,
                  title: 'Audio Sync Offset',
                  currentValueMs: currentActiveDelayMs,
                  onChanged: (newVal) {
                    onDelayChanged(newVal);
                    setModalState(() {
                      currentActiveDelayMs = newVal;
                    });
                  },
                ),
                const Divider(height: 1),

                _buildHeader(theme, 'TRACK SELECTION'),
                ...tracks.map((track) {
                  final title = track.title != null && track.title!.isNotEmpty
                      ? track.title!
                      : 'Track ${track.id}';
                  final lang =
                      track.language != null && track.language!.isNotEmpty
                      ? ' [${track.language!.toUpperCase()}]'
                      : '';
                  final displayName = '$title$lang';

                  return _buildTrackTile(
                    theme: theme,
                    title: displayName,
                    isSelected: track.id == selectedTrack.id,
                    onTap: () {
                      onSelected(track);
                      Navigator.pop(context);
                    },
                  );
                }),
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  static void showSleepTimerSettings({
    required BuildContext context,
    required String activeTimer,
    required ValueChanged<String> onSelected,
  }) {
    final List<String> timers = [
      'Off',
      '15 Minutes',
      '30 Minutes',
      '45 Minutes',
      '60 Minutes',
      'End of Video',
    ];

    VeilBottomSheet.show(
      context: context,
      title: 'Sleep Timer',
      subtitle: 'Automatically pause playback after timer',
      children: timers.map((timer) {
        return VeilBottomSheetTile(
          title: timer,
          leadingIcon: Icons.timer_rounded,
          isSelected: timer == activeTimer,
          onTap: () {
            onSelected(timer);
            Navigator.pop(context);
          },
        );
      }).toList(),
    );
  }

  static void showVideoInfo({
    required BuildContext context,
    required String fileName,
    required String path,
    required String fileSize,
    required String duration,
    required String aspectRatio,
    required int audioTracksCount,
    required int subtitleTracksCount,
    MediaDiagnostics? diagnostics,
    // Legacy fallbacks for when diagnostics are unavailable
    String? legacyResolution,
    String? legacyVideoCodec,
    String? legacyAudioCodec,
  }) {
    final theme = Theme.of(context);
    String folder = '';
    try {
      folder = File(path).parent.path.split(Platform.pathSeparator).last;
    } catch (_) {}
    if (folder.isEmpty) folder = 'Storage';

    // Build display values — prefer diagnostics, fall back to legacy
    final resolution =
        diagnostics?.resolutionString ?? legacyResolution ?? 'Unknown';
    final resolutionLabel = diagnostics?.resolutionLabel;
    final videoCodec =
        diagnostics?.videoCodecDisplayName ?? legacyVideoCodec ?? 'Unknown';
    final audioCodec =
        diagnostics?.audioCodecDisplayName ?? legacyAudioCodec ?? 'Unknown';
    final frameRate = diagnostics?.frameRateString ?? 'Unknown';
    final bitrate = diagnostics?.bitrateString ?? 'Unknown';
    final container = diagnostics?.containerDisplayName ?? 'Unknown';
    final pixelFormat = diagnostics?.pixelFormat;
    final channelLayout = diagnostics?.channelLayoutLabel;
    final audioSampleRate = diagnostics?.audioSampleRate != null
        ? '${(diagnostics!.audioSampleRate! / 1000.0).toStringAsFixed(1)} kHz'
        : null;
    final hwDecodeActive = diagnostics?.hwDecodeActive ?? false;
    final hwDecodeLabel = diagnostics?.hwDecodeDisplayName;
    final externalSubs = diagnostics?.externalSubtitleCount ?? 0;
    final videoSupport = diagnostics?.videoSupportLevel;
    final audioSupport = diagnostics?.audioSupportLevel;

    final subtitleTotal = subtitleTracksCount + externalSubs;

    VeilBottomSheet.show(
      context: context,
      title: 'Media Information',
      subtitle: fileName,
      children: [
        // ── File ──────────────────────────────────────────────────────────────
        _buildSectionHeader(theme, 'FILE'),
        _buildInfoRow(theme, 'File Name', fileName),
        _buildInfoRow(theme, 'Path', path),
        _buildInfoRow(theme, 'Folder', folder),
        _buildInfoRow(theme, 'File Size', fileSize),
        _buildInfoRow(theme, 'Duration', duration),

        // ── Container ─────────────────────────────────────────────────────────
        _buildSectionHeader(theme, 'CONTAINER'),
        _buildInfoRow(theme, 'Format', container),

        // ── Video ─────────────────────────────────────────────────────────────
        _buildSectionHeader(theme, 'VIDEO'),
        _buildInfoRowWithBadge(
          theme: theme,
          label: 'Codec',
          value: videoCodec,
          badge: videoSupport,
        ),
        _buildInfoRow(
          theme,
          'Resolution',
          resolutionLabel != null
              ? '$resolution  ($resolutionLabel)'
              : resolution,
        ),
        _buildInfoRow(theme, 'Aspect Ratio', aspectRatio),
        _buildInfoRow(theme, 'Frame Rate', frameRate),
        if (pixelFormat != null)
          _buildInfoRow(theme, 'Pixel Format', pixelFormat),
        _buildInfoRow(theme, 'Bitrate', bitrate),
        _buildInfoRowWithBadge(
          theme: theme,
          label: 'HW Decode',
          value: hwDecodeActive
              ? (hwDecodeLabel ?? 'Active')
              : 'Software (CPU)',
          badge: hwDecodeActive ? SupportLevel.full : null,
          badgeLabel: hwDecodeActive ? 'HW' : null,
          badgeColor: hwDecodeActive ? const Color(0xFF6366F1) : null,
        ),

        // ── Audio ─────────────────────────────────────────────────────────────
        _buildSectionHeader(theme, 'AUDIO'),
        _buildInfoRowWithBadge(
          theme: theme,
          label: 'Codec',
          value: audioCodec,
          badge: audioSupport,
        ),
        _buildInfoRow(
          theme,
          'Tracks',
          '$audioTracksCount track${audioTracksCount != 1 ? "s" : ""}',
        ),
        if (channelLayout != null)
          _buildInfoRow(theme, 'Channels', channelLayout),
        if (audioSampleRate != null)
          _buildInfoRow(theme, 'Sample Rate', audioSampleRate),

        // ── Subtitles ─────────────────────────────────────────────────────────
        _buildSectionHeader(theme, 'SUBTITLES'),
        _buildInfoRow(
          theme,
          'Tracks',
          '$subtitleTotal track${subtitleTotal != 1 ? "s" : ""}',
        ),
        if (externalSubs > 0)
          _buildInfoRow(
            theme,
            'External',
            '$externalSubs sidecar file${externalSubs != 1 ? "s" : ""} found',
          ),

        const SizedBox(height: 8),
      ],
    );
  }

  static Widget _buildSectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 20.0, bottom: 6.0),
      child: Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  static Widget _buildInfoRowWithBadge({
    required ThemeData theme,
    required String label,
    required String value,
    SupportLevel? badge,
    String? badgeLabel,
    Color? badgeColor,
  }) {
    Color? resolvedColor;
    String? resolvedLabel;

    if (badge != null) {
      switch (badge) {
        case SupportLevel.full:
          resolvedColor = badgeColor ?? const Color(0xFF10B981);
          resolvedLabel = badgeLabel ?? 'OK';
          break;
        case SupportLevel.limited:
          resolvedColor = const Color(0xFFF59E0B);
          resolvedLabel = badgeLabel ?? 'Limited';
          break;
        case SupportLevel.unsupported:
          resolvedColor = const Color(0xFFEF4444);
          resolvedLabel = badgeLabel ?? 'Unsupported';
          break;
      }
    } else if (badgeColor != null) {
      resolvedColor = badgeColor;
      resolvedLabel = badgeLabel;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                height: 1.4,
              ),
              softWrap: true,
            ),
          ),
          if (resolvedColor != null && resolvedLabel != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: resolvedColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: resolvedColor.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Text(
                resolvedLabel,
                style: TextStyle(
                  color: resolvedColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                height: 1.4,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  static void showAspectRatioSettings({
    required BuildContext context,
    required String currentRatio,
    required ValueChanged<String> onSelected,
  }) {
    final List<String> options = [
      'Fit',
      'Fill',
      'Stretch',
      '16:9',
      '4:3',
      'Original',
    ];

    VeilBottomSheet.show(
      context: context,
      title: 'Aspect Ratio',
      subtitle: 'Select video display layout',
      children: options.map((option) {
        return VeilBottomSheetTile(
          title: option,
          leadingIcon: Icons.aspect_ratio_rounded,
          isSelected: option == currentRatio,
          onTap: () {
            onSelected(option);
            Navigator.pop(context);
          },
        );
      }).toList(),
    );
  }

  static Widget _buildSyncOffsetAdjuster({
    required ThemeData theme,
    required String title,
    required int currentValueMs,
    required ValueChanged<int> onChanged,
  }) {
    final double seconds = currentValueMs / 1000.0;
    final String label = seconds == 0.0
        ? '0.0s (In Sync)'
        : '${seconds > 0.0 ? "+" : ""}${seconds.toStringAsFixed(1)}s';

    return StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Adjustment row
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.remove_circle_outline_rounded,
                          color: theme.colorScheme.onSurface,
                        ),
                        onPressed: () {
                          final newVal = currentValueMs - 100;
                          onChanged(newVal);
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.add_circle_outline_rounded,
                          color: theme.colorScheme.onSurface,
                        ),
                        onPressed: () {
                          final newVal = currentValueMs + 100;
                          onChanged(newVal);
                        },
                      ),
                    ],
                  ),
                  // Reset Button
                  if (currentValueMs != 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        onChanged(0);
                      },
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
