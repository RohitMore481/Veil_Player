import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/veil_theme.dart';
import '../../library/models/video_item.dart';
import '../../library/providers/media_provider.dart';

class FolderQueuePanel extends ConsumerStatefulWidget {
  final VideoItem? currentVideo;
  final List<VideoItem> videos;
  final bool isLoading;
  final ValueChanged<VideoItem> onVideoSelected;
  final VoidCallback onClose;

  const FolderQueuePanel({
    super.key,
    required this.currentVideo,
    required this.videos,
    required this.isLoading,
    required this.onVideoSelected,
    required this.onClose,
  });

  @override
  ConsumerState<FolderQueuePanel> createState() => _FolderQueuePanelState();
}

class _FolderQueuePanelState extends ConsumerState<FolderQueuePanel> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveVideo();
    });
  }

  @override
  void didUpdateWidget(FolderQueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentVideo?.id != widget.currentVideo?.id) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActiveVideo(),
      );
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  void _scrollToActiveVideo() {
    if (!mounted) return;
    final activeIndex = widget.videos.indexWhere(
      (v) =>
          v.id == widget.currentVideo?.id ||
          v.path == widget.currentVideo?.path,
    );
    if (activeIndex != -1 && _scrollController.hasClients) {
      final double viewportHeight =
          _scrollController.position.viewportDimension;
      final double targetOffset =
          (activeIndex * 68.0) - (viewportHeight / 2) + 34.0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, maxScroll),
        duration: VeilMotion.emphasized,
        curve: VeilMotion.curve,
      );
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter queue list based on search query
    final filteredVideos = widget.videos.where((video) {
      if (_searchQuery.isEmpty) return true;
      return video.title.toLowerCase().contains(_searchQuery);
    }).toList();

    return SafeArea(
      child: Column(
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Folder Videos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF222222), width: 1),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search videos...',
                  hintStyle: const TextStyle(
                    color: Colors.white24,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.white38,
                            size: 16,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Videos List
          Expanded(
            child: widget.isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                      strokeWidth: 1.5,
                    ),
                  )
                : filteredVideos.isEmpty
                ? Center(
                    child: Text(
                      'No videos found',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white38,
                      ),
                    ),
                  )
                : RepaintBoundary(
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: filteredVideos.length,
                      itemBuilder: (context, index) {
                        final video = filteredVideos[index];
                        final originalIndex = widget.videos.indexWhere(
                          (v) => v.id == video.id || v.path == video.path,
                        );
                        final isPlaying =
                            video.id == widget.currentVideo?.id ||
                            video.path == widget.currentVideo?.path;
                        final activeIndex = widget.videos.indexWhere(
                          (v) =>
                              v.id == widget.currentVideo?.id ||
                              v.path == widget.currentVideo?.path,
                        );
                        final isCompleted =
                            originalIndex != -1 &&
                            activeIndex != -1 &&
                            originalIndex < activeIndex;

                        return _QueueItem(
                          video: video,
                          isPlaying: isPlaying,
                          isCompleted: isCompleted,
                          accentColor: theme.colorScheme.primary,
                          onTap: () {
                            widget.onVideoSelected(video);
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueItem extends ConsumerWidget {
  final VideoItem video;
  final bool isPlaying;
  final bool isCompleted;
  final Color accentColor;
  final VoidCallback onTap;

  const _QueueItem({
    required this.video,
    required this.isPlaying,
    required this.isCompleted,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailAsync = ref.watch(videoThumbnailProvider(video));

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: isCompleted ? 0.45 : 1.0,
        child: Container(
          height: 68,
          padding: EdgeInsets.only(
            left: isPlaying ? 13.0 : 16.0,
            right: 16.0,
            top: 8.0,
            bottom: 8.0,
          ),
          decoration: BoxDecoration(
            color: isPlaying
                ? accentColor.withValues(alpha: 0.05)
                : Colors.transparent,
            border: Border(
              left: isPlaying
                  ? BorderSide(color: accentColor, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(
                color: isPlaying
                    ? accentColor.withValues(alpha: 0.15)
                    : const Color(0xFF111111),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Video Thumbnail
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isPlaying
                          ? accentColor.withValues(alpha: 0.3)
                          : const Color(0xFF1C1C1C),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: thumbnailAsync.when(
                    data: (path) {
                      if (path != null) {
                        return Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => const Icon(
                            Icons.movie_outlined,
                            color: Colors.white24,
                            size: 16,
                          ),
                        );
                      }
                      return const Icon(
                        Icons.movie_outlined,
                        color: Colors.white24,
                        size: 16,
                      );
                    },
                    loading: () => const Center(
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.0,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                    error: (err, stack) => const Icon(
                      Icons.movie_outlined,
                      color: Colors.white24,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Video Title & Size
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${isPlaying ? '▶ ' : ''}${video.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaying ? accentColor : Colors.white70,
                        fontSize: 13,
                        fontWeight: isPlaying
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (isPlaying) ...[
                          Icon(
                            Icons.play_arrow_rounded,
                            color: accentColor,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '${video.formattedDuration} • ${video.formattedSize}',
                          style: TextStyle(
                            color: isPlaying
                                ? accentColor.withValues(alpha: 0.7)
                                : Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isCompleted) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
