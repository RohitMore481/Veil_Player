import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/page_transitions.dart';
import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../../library/providers/media_provider.dart';
import '../../main/widgets/media_section_switcher.dart';
import '../models/audio_folder_item.dart';
import '../models/audio_item.dart';
import '../models/playlist.dart';
import '../providers/audio_library_providers.dart';
import '../providers/audio_pinned_folders_provider.dart';
import '../providers/audio_player_provider.dart';
import '../providers/playlists_provider.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/manage_audio_pinned_folders_dialog.dart';
import 'all_audio_tracks_screen.dart';
import 'audio_folder_detail_screen.dart';
import 'music_search_screen.dart';
import 'playlist_detail_screen.dart';

class MusicLibraryScreen extends ConsumerStatefulWidget {
  const MusicLibraryScreen({super.key});

  @override
  ConsumerState<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends ConsumerState<MusicLibraryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  IconData _getAudioFolderIcon(AudioFolderItem folder, List<String> pinnedPaths) {
    if (pinnedPaths.contains(folder.path)) return Icons.push_pin_rounded;
    final lower = folder.name.toLowerCase();
    if (lower.contains('download')) return Icons.download_rounded;
    if (lower.contains('music')) return Icons.music_note_rounded;
    if (lower.contains('podcast')) return Icons.podcasts_rounded;
    if (lower.contains('record')) return Icons.mic_rounded;
    if (lower.contains('telegram')) return Icons.telegram_rounded;
    if (lower.contains('whatsapp')) return Icons.audio_file_rounded;
    return Icons.folder_rounded;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final permission = ref.watch(audioPermissionProvider);
    final isPermissionDenied =
        permission == 'denied' || permission == 'permanently_denied';

    if (isPermissionDenied) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: VeilEmptyState(
            icon: Icons.shield_outlined,
            title: 'Audio Access Required',
            description:
                'Allow audio access to discover and play music tracks stored on your device.',
            buttonLabel: permission == 'denied'
                ? 'Grant Audio Permission'
                : 'Open App Settings',
            buttonIcon: permission == 'denied'
                ? Icons.key_rounded
                : Icons.settings_outlined,
            onButtonTap: () {
              if (permission == 'denied') {
                ref.read(audioPermissionProvider.notifier).requestPermission();
              } else {
                ref.read(audioPermissionProvider.notifier).openSettings();
              }
            },
          ),
        ),
      );
    }

    final paginatedState = ref.watch(allAudioTracksProvider);
    final recentTracks = ref.watch(recentlyPlayedAudioProvider);
    final foldersAsync = ref.watch(audioFoldersProvider);
    final playlists = ref.watch(playlistsProvider);
    final queueState = ref.watch(audioPlayerProvider);
    final isStorageManager = ref.watch(storageManagerProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: primary,
          backgroundColor: isDark ? const Color(0xFF16181D) : Colors.white,
          onRefresh: () async {
            ref.read(allAudioTracksProvider.notifier).refresh();
            ref.invalidate(audioFoldersProvider);
            ref.invalidate(recentlyPlayedAudioProvider);
            ref.invalidate(playlistsProvider);
            ref.invalidate(audioPinnedFoldersProvider);
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // Row 1: Shared App Header (Identical to Video LibraryScreen)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Image.asset(
                          'assets/images/header_logo.png',
                          height: 18,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.search_rounded,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                              size: 24,
                            ),
                            tooltip: 'Search Music',
                            onPressed: () {
                              Navigator.push(
                                context,
                                VeilPageRoute(
                                  builder: (_) => MusicSearchScreen(
                                      allTracks: paginatedState.tracks),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: isStorageManager
                                ? null
                                : () async {
                                    await ref
                                        .read(storageManagerProvider.notifier)
                                        .request();
                                    await ref
                                        .read(storageManagerProvider.notifier)
                                        .recheck();
                                  },
                            child: Tooltip(
                              message: isStorageManager
                                  ? 'Full storage access granted — silent file operations active'
                                  : 'Tap to enable silent file operations (no system dialogs)',
                              child: Icon(
                                isStorageManager
                                    ? Icons.shield_rounded
                                    : Icons.shield_outlined,
                                color: isStorageManager
                                    ? primary.withValues(alpha: 0.7)
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.3),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Row 2: Media Section Switcher (Directly below app header, identical alignment)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.0, 0, 16.0, 14.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MediaSectionSwitcher(),
                  ),
                ),
              ),

              // Storage Manager Permission Banner (if not granted)
              if (!isStorageManager)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GestureDetector(
                      onTap: () async {
                        await ref
                            .read(storageManagerProvider.notifier)
                            .request();
                        await ref
                            .read(storageManagerProvider.notifier)
                            .recheck();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: primary,
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Enable silent file operations — tap to grant full storage access',
                                style: TextStyle(
                                  color: primary.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: primary.withValues(alpha: 0.5),
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // SECTION 1: Primary Library Area / Continue Listening Hero
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recentTracks.isNotEmpty
                            ? 'Continue Listening'
                            : 'Music Library',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (recentTracks.isNotEmpty)
                        _AudioHeroContinueCard(
                          track: recentTracks.first,
                          trackList: recentTracks,
                        )
                      else
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              VeilPageRoute(
                                builder: (_) => const AllAudioTracksScreen(),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF070707)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF131313)
                                    : const Color(0xFFE5E7EB),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.music_note_outlined,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.15),
                                  size: 44,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Music you start playing will appear here',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.35),
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                VeilButton(
                                  label: 'Browse Songs',
                                  icon: Icons.queue_music_rounded,
                                  height: 32,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      VeilPageRoute(
                                        builder: (_) =>
                                            const AllAudioTracksScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // SECTION 2: Quick Access (Audio Folders)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 20.0, left: 16.0, right: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Quick Access',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          if (ref
                              .watch(audioPinnedFoldersProvider)
                              .isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) =>
                                      const ManageAudioPinnedFoldersDialog(),
                                );
                              },
                              child: Text(
                                'Manage',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      foldersAsync.when(
                        loading: () => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(
                              color: primary,
                              strokeWidth: 1.5,
                            ),
                          ),
                        ),
                        error: (err, stack) => Text(
                          'Failed to load folders: $err',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                        data: (folders) {
                          final pinnedPaths =
                              ref.watch(audioPinnedFoldersProvider);
                          final lastPlayedTrack = recentTracks.isNotEmpty
                              ? recentTracks.first
                              : null;

                          // Deduplicated Quick Access folder suggestions
                          final quickAccessFolders = folders.where((f) {
                            if (pinnedPaths.contains(f.path)) return true;
                            final nameLower = f.name.toLowerCase();
                            return nameLower == 'music' ||
                                nameLower == 'download' ||
                                nameLower == 'downloads' ||
                                nameLower == 'audio' ||
                                nameLower == 'songs' ||
                                nameLower == 'podcasts' ||
                                nameLower == 'recordings';
                          }).toList();

                          if (quickAccessFolders.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No folders containing audio detected',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.38),
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }

                          // Identify last-played folder for highlight
                          AudioFolderItem? lastPlayedFolder;
                          if (lastPlayedTrack != null) {
                            for (final f in quickAccessFolders) {
                              if (f.path.toLowerCase() ==
                                      lastPlayedTrack.folderPath.toLowerCase() ||
                                  lastPlayedTrack.path
                                      .toLowerCase()
                                      .startsWith(f.path.toLowerCase())) {
                                lastPlayedFolder = f;
                                break;
                              }
                            }
                          }

                          return Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: quickAccessFolders.map((folder) {
                              final isLastPlayed = folder == lastPlayedFolder;
                              return _AudioQuickAccessChip(
                                folder: folder,
                                icon: _getAudioFolderIcon(folder, pinnedPaths),
                                accentColor: primary,
                                isLastPlayed: isLastPlayed,
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // SECTION 3: Playlists (Restrained, offline collections)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 24.0, left: 16.0, right: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Playlists',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) =>
                                    const CreatePlaylistDialog(),
                              );
                            },
                            child: Text(
                              '+ New Playlist',
                              style: TextStyle(
                                color: primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (playlists.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 18, horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF070707)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF131313)
                                  : const Color(0xFFE5E7EB),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.playlist_add_rounded,
                                color: primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Create custom playlists from your offline audio files.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              VeilButton(
                                label: 'Create',
                                height: 30,
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) =>
                                        const CreatePlaylistDialog(),
                                  );
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          children: playlists.map((pl) {
                            final isPlaylistActive =
                                queueState.activePlaylistId == pl.id ||
                                    (queueState.currentTrack != null &&
                                        pl.tracks.any((t) =>
                                            t.id == queueState.currentTrack!.id));
                            final isPlaying =
                                isPlaylistActive && queueState.isPlaying;

                            return _PlaylistListTile(
                              playlist: pl,
                              accentColor: primary,
                              isHighlighted: isPlaylistActive,
                              isPlaying: isPlaying,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  VeilPageRoute(
                                    builder: (_) => PlaylistDetailScreen(
                                        playlistId: pl.id),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom clearance spacing (MiniPlayer + Nav bar safe zone)
              const SliverToBoxAdapter(
                child: SizedBox(height: 120),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Consistent with Video's _HeroContinueCard
class _AudioHeroContinueCard extends ConsumerStatefulWidget {
  final AudioTrackItem track;
  final List<AudioTrackItem> trackList;

  const _AudioHeroContinueCard({
    required this.track,
    required this.trackList,
  });

  @override
  ConsumerState<_AudioHeroContinueCard> createState() =>
      _AudioHeroContinueCardState();
}

class _AudioHeroContinueCardState
    extends ConsumerState<_AudioHeroContinueCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isHighlighted = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final currentPlaying = ref.watch(audioPlayerProvider).currentTrack;
    final isPlaying =
        currentPlaying?.id == widget.track.id && ref.watch(audioPlayerProvider).isPlaying;

    return GestureDetector(
      onTapDown: (_) {
        _animController.forward();
        setState(() => _isHighlighted = true);
      },
      onTapUp: (_) {
        _animController.reverse();
        setState(() => _isHighlighted = false);
        ref
            .read(audioPlayerProvider.notifier)
            .playTrackList(widget.trackList, initialIndex: 0);
      },
      onTapCancel: () {
        _animController.reverse();
        setState(() => _isHighlighted = false);
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              decoration: BoxDecoration(
                color: _isHighlighted
                    ? theme.cardTheme.color?.withValues(alpha: 0.8)
                    : theme.cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isHighlighted
                      ? primary.withValues(alpha: 0.3)
                      : (isDark
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFE5E7EB)),
                  width: 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.music_note_rounded,
                        color: primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${widget.track.artist} • ${widget.track.folderName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    VeilButton(
                      height: 36,
                      label: isPlaying ? 'Pause' : 'Play',
                      icon: isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: () {
                        if (isPlaying) {
                          ref.read(audioPlayerProvider.notifier).pause();
                        } else {
                          ref
                              .read(audioPlayerProvider.notifier)
                              .playTrackList(widget.trackList, initialIndex: 0);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Consistent with Video's _QuickAccessChip
class _AudioQuickAccessChip extends StatefulWidget {
  final AudioFolderItem folder;
  final IconData icon;
  final Color accentColor;
  final bool isLastPlayed;

  const _AudioQuickAccessChip({
    required this.folder,
    required this.icon,
    required this.accentColor,
    this.isLastPlayed = false,
  });

  @override
  State<_AudioQuickAccessChip> createState() => _AudioQuickAccessChipState();
}

class _AudioQuickAccessChipState extends State<_AudioQuickAccessChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) {
        _animController.forward();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        _animController.reverse();
        setState(() => _isPressed = false);
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          VeilPageRoute(
            builder: (_) => AudioFolderDetailScreen(folder: widget.folder),
          ),
        );
      },
      onTapCancel: () {
        _animController.reverse();
        setState(() => _isPressed = false);
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: _isPressed ? 0.75 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isLastPlayed
                  ? widget.accentColor.withValues(alpha: 0.12)
                  : (isDark
                      ? const Color(0xFF0A0A0A)
                      : const Color(0xFFF3F4F6)),
              border: Border.all(
                color: _isPressed
                    ? widget.accentColor.withValues(alpha: 0.5)
                    : (widget.isLastPlayed
                        ? widget.accentColor
                        : (isDark
                            ? const Color(0xFF161616)
                            : const Color(0xFFE5E7EB))),
                width: widget.isLastPlayed ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.isLastPlayed && !_isPressed
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.2),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isLastPlayed
                      ? Icons.play_circle_fill_rounded
                      : widget.icon,
                  color: widget.accentColor,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.folder.name,
                  style: TextStyle(
                    color: widget.isLastPlayed
                        ? widget.accentColor
                        : theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: widget.isLastPlayed
                        ? FontWeight.bold
                        : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.folder.trackCount}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 10,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Consistent with Video's _FolderListTile for Playlists
class _PlaylistListTile extends StatelessWidget {
  final Playlist playlist;
  final Color accentColor;
  final bool isHighlighted;
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlaylistListTile({
    required this.playlist,
    required this.accentColor,
    this.isHighlighted = false,
    this.isPlaying = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isHighlighted
            ? accentColor.withValues(alpha: 0.10)
            : (isDark ? const Color(0xFF070707) : const Color(0xFFF3F4F6)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlighted
              ? accentColor.withValues(alpha: 0.75)
              : (isDark ? const Color(0xFF131313) : const Color(0xFFE5E7EB)),
          width: isHighlighted ? 1.5 : 1.0,
        ),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.20),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isHighlighted
                ? accentColor.withValues(alpha: 0.20)
                : (isDark
                    ? const Color(0xFF131313)
                    : const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPlaying
                ? Icons.graphic_eq_rounded
                : (isHighlighted
                    ? Icons.play_circle_fill_rounded
                    : Icons.playlist_play_rounded),
            color: accentColor,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isHighlighted
                      ? accentColor
                      : theme.colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight:
                      isHighlighted ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            if (isHighlighted) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isPlaying ? 'PLAYING' : 'LAST PLAYED',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${playlist.formattedTrackCount}  •  ${playlist.formattedTotalDuration}',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
            fontSize: 11.5,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isHighlighted
              ? accentColor.withValues(alpha: 0.7)
              : theme.colorScheme.onSurface.withValues(alpha: 0.24),
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }
}
