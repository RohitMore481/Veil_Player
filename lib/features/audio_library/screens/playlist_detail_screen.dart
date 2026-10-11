import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_item.dart';
import '../models/playlist.dart';
import '../providers/audio_player_provider.dart';
import '../providers/playlists_provider.dart';
import '../widgets/audio_track_overflow_sheet.dart';
import '../widgets/create_playlist_dialog.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final playlists = ref.watch(playlistsProvider);
    final playlist = playlists.cast<Playlist?>().firstWhere(
          (p) => p?.id == playlistId,
          orElse: () => null,
        );

    if (playlist == null) {
      return Scaffold(
        backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: Text('Playlist not found')),
      );
    }

    final tracks = playlist.tracks;
    final currentPlaying = ref.watch(audioPlayerProvider).currentTrack;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: isDark ? Colors.white70 : Colors.black87),
            color: isDark ? const Color(0xFF1E2228) : Colors.white,
            onSelected: (val) async {
              if (val == 'rename') {
                showDialog(
                  context: context,
                  builder: (ctx) =>
                      CreatePlaylistDialog(initialPlaylist: playlist),
                );
              } else if (val == 'add_to_queue') {
                if (tracks.isNotEmpty) {
                  ref.read(audioPlayerProvider.notifier).addFolder(tracks);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Added ${tracks.length} tracks to playback queue'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else if (val == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor:
                        isDark ? const Color(0xFF16181D) : Colors.white,
                    title: const Text('Delete Playlist?'),
                    content: Text(
                      'Are you sure you want to delete "${playlist.name}"? Audio files will NOT be deleted from your device.',
                      style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && context.mounted) {
                  await ref
                      .read(playlistsProvider.notifier)
                      .deletePlaylist(playlist.id);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Text('Rename Playlist'),
              ),
              const PopupMenuItem(
                value: 'add_to_queue',
                child: Text('Add to Queue'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child:
                    Text('Delete Playlist', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playlist Header Area
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.playlist_play_rounded,
                    color: primary,
                    size: 46,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${playlist.formattedTrackCount}  •  ${playlist.formattedTotalDuration}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Play All / Shuffle All Action Buttons
          if (tracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded,
                          color: Colors.black, size: 20),
                      label: const Text(
                        'Play All',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () {
                        ref
                            .read(audioPlayerProvider.notifier)
                            .playTrackList(tracks,
                                initialIndex: 0, playlistId: playlist.id);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.shuffle_rounded, color: primary, size: 18),
                      label: Text(
                        'Shuffle',
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : const Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () {
                        final shuffled = List<AudioTrackItem>.from(tracks)
                          ..shuffle();
                        ref
                            .read(audioPlayerProvider.notifier)
                            .playTrackList(shuffled,
                                initialIndex: 0, playlistId: playlist.id);
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Track List
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.queue_music_rounded,
                          size: 56,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Playlist is empty',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add tracks from All Tracks in your music library.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: tracks.length,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      ref
                          .read(playlistsProvider.notifier)
                          .reorderTracks(playlist.id, oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final isCurrent = currentPlaying?.id == track.id;

                      return Dismissible(
                        key: ValueKey('swipe_queue_pl_${track.id}_$index'),
                        direction: DismissDirection.startToEnd,
                        confirmDismiss: (direction) async {
                          HapticFeedback.mediumImpact();
                          ref.read(audioPlayerProvider.notifier).addTrack(track);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.queue_music_rounded,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Added to queue: "${track.title}"',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.queue_music_rounded,
                                  color: Colors.black, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Add to Queue',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        child: Container(
                          key: ValueKey('pl_${track.id}_$index'),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? primary.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? primary.withValues(alpha: 0.18)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.04)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isCurrent
                                    ? Icons.graphic_eq_rounded
                                    : Icons.music_note_rounded,
                                color: isCurrent
                                    ? primary
                                    : (isDark
                                        ? Colors.white54
                                        : Colors.black45),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight:
                                    isCurrent ? FontWeight.bold : FontWeight.w500,
                                color: isCurrent
                                    ? primary
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                            subtitle: Text(
                              '${track.artist}  •  ${track.formattedDuration}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      builder: (ctx) =>
                                          AudioTrackOverflowSheet(
                                              track: track),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    size: 20,
                                  ),
                                  tooltip: 'Remove from playlist',
                                  onPressed: () {
                                    ref
                                        .read(playlistsProvider.notifier)
                                        .removeTrackFromPlaylist(
                                            playlist.id, index);
                                  },
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              final current = ref.read(audioPlayerProvider).currentTrack;
                              if (current?.id == track.id) {
                                ref.read(audioPlayerProvider.notifier).togglePlayPause();
                              } else {
                                ref.read(audioPlayerProvider.notifier).playTrackList(
                                      tracks,
                                      initialIndex: index,
                                      playlistId: playlist.id,
                                    );
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
