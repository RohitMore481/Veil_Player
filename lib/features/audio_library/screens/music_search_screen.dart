import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_item.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/audio_track_overflow_sheet.dart';

class MusicSearchScreen extends ConsumerStatefulWidget {
  final List<AudioTrackItem> allTracks;

  const MusicSearchScreen({
    super.key,
    required this.allTracks,
  });

  @override
  ConsumerState<MusicSearchScreen> createState() => _MusicSearchScreenState();
}

class _MusicSearchScreenState extends ConsumerState<MusicSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<AudioTrackItem> _filteredTracks = [];

  @override
  void initState() {
    super.initState();
    _filteredTracks = widget.allTracks;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredTracks = widget.allTracks;
      } else {
        _filteredTracks = widget.allTracks.where((track) {
          final title = track.title.toLowerCase();
          final artist = track.artist.toLowerCase();
          final album = track.album.toLowerCase();
          return title.contains(query) ||
              artist.contains(query) ||
              album.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              focusNode: _focusNode,
              autofocus: true,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            if (_searchController.text.isNotEmpty)
              Text(
                '${_filteredTracks.length} ${_filteredTracks.length == 1 ? 'track' : 'tracks'} found',
                style: TextStyle(
                  fontSize: 11,
                  color: primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_rounded,
                  color: isDark ? Colors.white54 : Colors.black54),
              onPressed: () {
                _searchController.clear();
              },
            ),
        ],
      ),
      body: _filteredTracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 56,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No songs found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try searching with a different term',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _filteredTracks.length,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
              itemBuilder: (context, index) {
                final track = _filteredTracks[index];
                final currentPlaying =
                    ref.watch(audioPlayerProvider).currentTrack;
                final isCurrent = currentPlaying?.id == track.id;

                return Dismissible(
                  key: ValueKey('swipe_queue_search_${track.id}_$index'),
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
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      leading: Container(
                        width: 44,
                        height: 44,
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
                              : (isDark ? Colors.white54 : Colors.black45),
                          size: 22,
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
                      trailing: IconButton(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: isDark ? Colors.white54 : Colors.black45,
                          size: 20,
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) =>
                                AudioTrackOverflowSheet(track: track),
                          );
                        },
                      ),
                      onTap: () {
                        ref.read(audioPlayerProvider.notifier).playTrackList(
                              _filteredTracks,
                              initialIndex: index,
                            );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
