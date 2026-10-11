import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../models/audio_item.dart';
import '../models/audio_folder_item.dart';
import '../providers/audio_library_providers.dart';
import '../providers/audio_pinned_folders_provider.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/audio_track_overflow_sheet.dart';

class AudioFolderDetailScreen extends ConsumerStatefulWidget {
  final AudioFolderItem folder;

  const AudioFolderDetailScreen({
    super.key,
    required this.folder,
  });

  @override
  ConsumerState<AudioFolderDetailScreen> createState() =>
      _AudioFolderDetailScreenState();
}

class _AudioFolderDetailScreenState
    extends ConsumerState<AudioFolderDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(folderAudioTracksProvider(widget.folder.path).notifier)
          .loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final paginated =
        ref.watch(folderAudioTracksProvider(widget.folder.path));
    final tracks = paginated.tracks;
    final isPinned =
        ref.watch(audioPinnedFoldersProvider).contains(widget.folder.path);
    final currentPlaying = ref.watch(audioPlayerProvider).currentTrack;
    final recentTracks = ref.watch(recentlyPlayedAudioProvider);
    final lastPlayedTrack =
        recentTracks.isNotEmpty ? recentTracks.first : null;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Navigation Header Bar (Consistent with Video FolderBrowserScreen)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
              child: Row(
                children: [
                  VeilButton(
                    type: VeilButtonType.icon,
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Storage',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.black26, size: 16),
                        Expanded(
                          child: Text(
                            widget.folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  VeilButton(
                    type: VeilButtonType.icon,
                    icon: isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    onTap: () {
                      ref
                          .read(audioPinnedFoldersProvider.notifier)
                          .togglePin(widget.folder.path);
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isPinned
                              ? 'Unpinned from Quick Access'
                              : 'Pinned to Quick Access'),
                          backgroundColor: isDark
                              ? const Color(0xFF111111)
                              : const Color(0xFFF3F4F6),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            Divider(
              color: isDark
                  ? const Color(0xFF111111)
                  : const Color(0xFFE5E7EB),
              height: 1,
            ),

            // Play All / Shuffle All Header
            if (tracks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded,
                            color: Colors.black, size: 20),
                        label: const Text(
                          'Play All',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold),
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
                              .playTrackList(tracks, initialIndex: 0);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.shuffle_rounded,
                            color: primary, size: 18),
                        label: Text(
                          'Shuffle All',
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          final shuffled =
                              List<AudioTrackItem>.from(tracks)..shuffle();
                          ref
                              .read(audioPlayerProvider.notifier)
                              .playTrackList(shuffled, initialIndex: 0);
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // Track List
            Expanded(
              child: paginated.isLoading && tracks.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                          color: primary, strokeWidth: 1.5),
                    )
                  : tracks.isEmpty
                      ? const VeilEmptyState(
                          icon: Icons.folder_open_rounded,
                          title: 'Empty Folder',
                          description:
                              'This folder contains no playable audio tracks.',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          itemCount: tracks.length +
                              (paginated.hasMore ? 1 : 0),
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 120),
                          itemBuilder: (context, index) {
                            if (index == tracks.length) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                      color: primary, strokeWidth: 1.5),
                                ),
                              );
                            }

                            final track = tracks[index];
                            final isCurrent =
                                currentPlaying?.id == track.id;
                            final isLastPlayed = !isCurrent &&
                                lastPlayedTrack != null &&
                                lastPlayedTrack.id == track.id;

                            return Dismissible(
                              key: ValueKey('swipe_queue_folder_${track.id}_$index'),
                              direction: DismissDirection.startToEnd,
                              confirmDismiss: (direction) async {
                                HapticFeedback.mediumImpact();
                                ref
                                    .read(audioPlayerProvider.notifier)
                                    .addTrack(track);
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
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
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? primary.withValues(alpha: 0.08)
                                      : isLastPlayed
                                          ? (isDark
                                              ? const Color(0xFF0F0F0F)
                                              : const Color(0xFFF3F4F6))
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isCurrent
                                      ? Border.all(
                                          color: primary
                                              .withValues(alpha: 0.4),
                                          width: 1)
                                      : isLastPlayed
                                          ? Border.all(
                                              color: isDark
                                                  ? const Color(0xFF1E1E1E)
                                                  : const Color(0xFFE5E7EB),
                                              width: 1)
                                          : null,
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
                                              ? Colors.white
                                                  .withValues(alpha: 0.06)
                                              : Colors.black
                                                  .withValues(alpha: 0.04)),
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
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isCurrent
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                            color: isCurrent
                                                ? primary
                                                : (isDark
                                                    ? Colors.white
                                                    : Colors.black87),
                                          ),
                                        ),
                                      ),
                                      if (isLastPlayed) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color:
                                                primary.withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: primary
                                                    .withValues(alpha: 0.35),
                                                width: 0.8),
                                          ),
                                          child: Text(
                                            'LAST PLAYED',
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                              color: primary,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${track.artist}  •  ${track.formattedDuration}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black45,
                                    ),
                                  ),
                                  trailing: IconButton(
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
                                  onTap: () {
                                    ref
                                        .read(audioPlayerProvider.notifier)
                                        .playTrackList(tracks,
                                            initialIndex: index);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
