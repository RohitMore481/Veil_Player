import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../models/audio_item.dart';
import '../providers/audio_library_providers.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/audio_track_overflow_sheet.dart';
import 'music_search_screen.dart';

enum AudioSortOption {
  title,
  artist,
  duration,
  dateAdded,
}

class AllAudioTracksScreen extends ConsumerStatefulWidget {
  const AllAudioTracksScreen({super.key});

  @override
  ConsumerState<AllAudioTracksScreen> createState() =>
      _AllAudioTracksScreenState();
}

class _AllAudioTracksScreenState extends ConsumerState<AllAudioTracksScreen> {
  AudioSortOption _sortOption = AudioSortOption.title;
  final ScrollController _scrollController = ScrollController();

  final Set<String> _selectedTrackIds = {};
  bool get _isMultiSelecting => _selectedTrackIds.isNotEmpty;

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
      ref.read(allAudioTracksProvider.notifier).loadNextPage();
    }
  }

  List<AudioTrackItem> _applySort(List<AudioTrackItem> list) {
    final sorted = List<AudioTrackItem>.from(list);
    switch (_sortOption) {
      case AudioSortOption.title:
        sorted.sort((a, b) => naturalCompare(a.title, b.title));
        break;
      case AudioSortOption.artist:
        sorted.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case AudioSortOption.duration:
        sorted.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case AudioSortOption.dateAdded:
        sorted.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
    }
    return sorted;
  }

  String _getSortLabel(AudioSortOption option) {
    switch (option) {
      case AudioSortOption.title:
        return 'Title';
      case AudioSortOption.artist:
        return 'Artist';
      case AudioSortOption.duration:
        return 'Duration';
      case AudioSortOption.dateAdded:
        return 'Recent';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final paginated = ref.watch(allAudioTracksProvider);
    final currentPlaying = ref.watch(audioPlayerProvider).currentTrack;
    final totalTracks = ref.watch(totalAudioTracksCountProvider);
    final count = totalTracks > 0 ? totalTracks : paginated.tracks.length;

    final displayedTracks = _applySort(paginated.tracks);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar (Consistent with Veil navigation)
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
                        Text(
                          'Library',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.black26, size: 16),
                        Expanded(
                          child: Text(
                            'All Songs ($count)',
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
                  IconButton(
                    icon: Icon(Icons.search_rounded,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7)),
                    tooltip: 'Search Songs',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => MusicSearchScreen(
                              allTracks: paginated.tracks),
                        ),
                      );
                    },
                  ),
                  PopupMenuButton<AudioSortOption>(
                    padding: EdgeInsets.zero,
                    icon: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF14171A)
                            : const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sort_rounded,
                              size: 16,
                              color: isDark ? Colors.white60 : Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            _getSortLabel(_sortOption),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    color: isDark ? const Color(0xFF1E2228) : Colors.white,
                    onSelected: (opt) {
                      setState(() {
                        _sortOption = opt;
                      });
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: AudioSortOption.title,
                        child: Text('Title (A-Z)'),
                      ),
                      const PopupMenuItem(
                        value: AudioSortOption.artist,
                        child: Text('Artist'),
                      ),
                      const PopupMenuItem(
                        value: AudioSortOption.duration,
                        child: Text('Duration (Longest)'),
                      ),
                      const PopupMenuItem(
                        value: AudioSortOption.dateAdded,
                        child: Text('Recently Added'),
                      ),
                    ],
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
            if (displayedTracks.isNotEmpty && !_isMultiSelecting)
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
                          ref.read(audioPlayerProvider.notifier).playTrackList(
                                displayedTracks,
                                initialIndex: 0,
                              );
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
                              List<AudioTrackItem>.from(displayedTracks)
                                ..shuffle();
                          ref.read(audioPlayerProvider.notifier).playTrackList(
                                shuffled,
                                initialIndex: 0,
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // Multi-selection bar
            if (_isMultiSelecting)
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Text(
                      '${_selectedTrackIds.length} selected',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Playlist',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(foregroundColor: primary),
                      onPressed: () {
                        final selectedTracks = displayedTracks
                            .where((t) => _selectedTrackIds.contains(t.id))
                            .toList();
                        if (selectedTracks.isNotEmpty) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) =>
                                AddToPlaylistSheet(tracks: selectedTracks),
                          );
                        }
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.queue_music_rounded, size: 18),
                      label: const Text('Queue'),
                      style: TextButton.styleFrom(foregroundColor: primary),
                      onPressed: () {
                        final selectedTracks = displayedTracks
                            .where((t) => _selectedTrackIds.contains(t.id))
                            .toList();
                        ref
                            .read(audioPlayerProvider.notifier)
                            .addMultipleToQueue(selectedTracks);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Added ${selectedTracks.length} tracks to queue'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        setState(() => _selectedTrackIds.clear());
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: isDark ? Colors.white70 : Colors.black87,
                          size: 20),
                      onPressed: () =>
                          setState(() => _selectedTrackIds.clear()),
                    ),
                  ],
                ),
              ),

            // Content List
            Expanded(
              child: RefreshIndicator(
                color: primary,
                onRefresh: () async {
                  ref.read(allAudioTracksProvider.notifier).refresh();
                },
                child: displayedTracks.isEmpty && !paginated.isLoading
                    ? const VeilEmptyState(
                        icon: Icons.music_off_outlined,
                        title: 'No audio tracks found',
                        description:
                            'Supported audio tracks on your device will appear here.',
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 160),
                        itemCount: displayedTracks.length +
                            (paginated.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == displayedTracks.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                    color: primary, strokeWidth: 1.5),
                              ),
                            );
                          }

                          final track = displayedTracks[index];
                          final isCurrent = currentPlaying?.id == track.id;

                          final isSelected =
                              _selectedTrackIds.contains(track.id);

                          final trackWidget = Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primary.withValues(alpha: 0.16)
                                  : isCurrent
                                      ? primary.withValues(alpha: 0.10)
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isCurrent
                                  ? Border.all(
                                      color: primary.withValues(alpha: 0.45),
                                      width: 1)
                                  : null,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2),
                              leading: _isMultiSelecting
                                  ? Checkbox(
                                      value: isSelected,
                                      activeColor: primary,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedTrackIds.add(track.id);
                                          } else {
                                            _selectedTrackIds.remove(track.id);
                                          }
                                        });
                                      },
                                    )
                                  : Container(
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
                                        borderRadius:
                                            BorderRadius.circular(10),
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
                              trailing: _isMultiSelecting
                                  ? null
                                  : IconButton(
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
                              onLongPress: () {
                                setState(() {
                                  if (_selectedTrackIds.contains(track.id)) {
                                    _selectedTrackIds.remove(track.id);
                                  } else {
                                    _selectedTrackIds.add(track.id);
                                  }
                                });
                              },
                              onTap: () {
                                if (_isMultiSelecting) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedTrackIds.remove(track.id);
                                    } else {
                                      _selectedTrackIds.add(track.id);
                                    }
                                  });
                                } else {
                                  final current = ref.read(audioPlayerProvider).currentTrack;
                                  if (current?.id == track.id) {
                                    ref.read(audioPlayerProvider.notifier).togglePlayPause();
                                  } else {
                                    ref
                                        .read(audioPlayerProvider.notifier)
                                        .playTrackList(
                                          displayedTracks,
                                          initialIndex: index,
                                        );
                                  }
                                }
                              },
                            ),
                          );

                          if (_isMultiSelecting) {
                            return trackWidget;
                          }

                          return Dismissible(
                            key: ValueKey('swipe_queue_all_${track.id}_$index'),
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
                            child: trackWidget,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
