import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_card.dart';
import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../player/screens/player_screen.dart';
import '../../../core/utils/page_transitions.dart';
import '../../library/providers/media_provider.dart';
import '../../library/models/video_item.dart';
import '../../library/widgets/library_bottom_sheets.dart';
import '../../library/providers/selection_provider.dart';
import '../../file_operations/providers/pending_operation_provider.dart';
import '../../file_operations/providers/file_clipboard_provider.dart';
import '../../file_operations/widgets/file_clipboard_bar.dart';

class FolderBrowserScreen extends ConsumerStatefulWidget {
  final String? initialFolder;
  final bool isQuickAccess;

  const FolderBrowserScreen({
    super.key,
    this.initialFolder,
    this.isQuickAccess = false,
  });

  @override
  ConsumerState<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends ConsumerState<FolderBrowserScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Navigation path tracking
  late final List<String> _currentPath;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _currentPath = ['root'];
    if (widget.initialFolder != null) {
      _currentPath.add(widget.initialFolder!);
    }
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final currentFolder = _currentPath.last;
    if (currentFolder == 'root') return;

    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      ref.read(folderVideosProvider(currentFolder).notifier).loadNextPage();
    }
  }

  void _navigateToFolder(String name) {
    if (_currentPath.isNotEmpty && _currentPath.last == name) return;
    setState(() {
      _currentPath.add(name);
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
  }

  bool _navigateBack() {
    if (widget.isQuickAccess) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return true;
    }
    if (_currentPath.length > 1) {
      setState(() {
        _currentPath.removeLast();
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final crossAxisCount = isLandscape ? 4 : 2;

    final String currentFolder = _currentPath.last;

    return PopScope(
      canPop: (widget.isQuickAccess || _currentPath.length <= 1) && !ref.watch(selectionModeProvider),
      onPopInvokedWithResult: (didPop, result) {
        if (ref.read(selectionModeProvider)) {
          ref.read(selectedVideosProvider.notifier).clear();
          return;
        }
        if (!didPop) {
          _navigateBack();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Navigation Header Bar
              Consumer(
                builder: (context, ref, child) {
                  final isSelectionMode = ref.watch(selectionModeProvider);
                  final selectedCount = ref.watch(selectedVideosProvider).length;
                  
                  if (isSelectionMode) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      child: Row(
                        children: [
                          VeilButton(
                            type: VeilButtonType.icon,
                            icon: Icons.close_rounded,
                            onTap: () {
                              ref.read(selectedVideosProvider.notifier).clear();
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$selectedCount Selected',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.select_all_rounded, color: theme.colorScheme.onSurface),
                            onPressed: () {
                              final currentFolder = _currentPath.last;
                              if (currentFolder != 'root') {
                                final videos = ref.read(folderVideosProvider(currentFolder)).videos;
                                ref.read(selectedVideosProvider.notifier).selectAll(videos.map((v) => v.id).toList());
                              }
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.content_cut_rounded, color: theme.colorScheme.primary),
                            tooltip: 'Cut / Move',
                            onPressed: () {
                              final selectedIds = ref.read(selectedVideosProvider);
                              if (selectedIds.isEmpty) return;
                              final currentFolder = _currentPath.last;
                              final videos = ref.read(folderVideosProvider(currentFolder)).videos;
                              final selectedVideos = videos.where((v) => selectedIds.contains(v.id)).toList();
                              ref.read(fileClipboardProvider.notifier).moveBatch(selectedVideos, currentFolder);
                              ref.read(selectedVideosProvider.notifier).clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.content_cut_rounded, color: Colors.white, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('${selectedVideos.length} video${selectedVideos.length > 1 ? 's' : ''} ready to move. Open a folder to paste.')),
                                    ],
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.content_copy_rounded, color: theme.colorScheme.onSurface),
                            tooltip: 'Copy',
                            onPressed: () {
                              final selectedIds = ref.read(selectedVideosProvider);
                              if (selectedIds.isEmpty) return;
                              final currentFolder = _currentPath.last;
                              final videos = ref.read(folderVideosProvider(currentFolder)).videos;
                              final selectedVideos = videos.where((v) => selectedIds.contains(v.id)).toList();
                              ref.read(fileClipboardProvider.notifier).copyBatch(selectedVideos, currentFolder);
                              ref.read(selectedVideosProvider.notifier).clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.content_copy_rounded, color: Colors.white, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('${selectedVideos.length} video${selectedVideos.length > 1 ? 's' : ''} copied. Open a folder to paste.')),
                                    ],
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                            onPressed: () async {
                              final selectedIds = ref.read(selectedVideosProvider);
                              if (selectedIds.isEmpty) return;
                              
                              final currentFolder = _currentPath.last;
                              final videos = ref.read(folderVideosProvider(currentFolder)).videos;
                              final selectedVideos = videos.where((v) => selectedIds.contains(v.id)).toList();
                              
                              // Show confirmation dialog for batch delete
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: theme.colorScheme.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB), width: 1),
                                  ),
                                  title: const Text('Delete Videos', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  content: Text('Are you sure you want to delete ${selectedIds.length} videos?', style: TextStyle(color: theme.colorScheme.onSurface)),
                                  actions: [
                                    TextButton(
                                      child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                                      onPressed: () => Navigator.pop(ctx, false),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                      child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                      onPressed: () => Navigator.pop(ctx, true),
                                    ),
                                  ],
                                ),
                              );
                              
                              if (confirm == true) {
                                final ids = selectedVideos.map((v) => v.id).toList();
                                final paths = selectedVideos.map((v) => v.path).toList();
                                final manager = ref.read(pendingOperationManagerProvider);
                                
                                ref.read(selectedVideosProvider.notifier).clear();
                                
                                final result = await manager.execute(BatchDeleteVideoOp(
                                  ids: ids,
                                  paths: paths,
                                  folderNames: {currentFolder},
                                ));
                                
                                if (!context.mounted) return;
                                if (result.$1) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                          const SizedBox(width: 10),
                                          Text(result.$2),
                                        ],
                                      ),
                                      backgroundColor: const Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                } else if (result.$2.isNotEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.$2)));
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: (_currentPath.length > 1 || widget.isQuickAccess) ? 8.0 : 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        if (_currentPath.length > 1 || widget.isQuickAccess) ...[
                          VeilButton(
                            type: VeilButtonType.icon,
                            icon: Icons.arrow_back_ios_new_rounded,
                            onTap: () {
                              _navigateBack();
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: _currentPath.asMap().entries.map((entry) {
                                final int index = entry.key;
                                final String pathName = entry.value;
                                final bool isLast = index == _currentPath.length - 1;
                                final displayName = pathName == 'root'
                                    ? (widget.isQuickAccess ? 'Quick Access' : 'Storage')
                                    : pathName;

                                return Row(
                                  children: [
                                    if (index > 0)
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.black26,
                                        size: 16,
                                      ),
                                    GestureDetector(
                                      onTap: () {
                                        if (!isLast) {
                                          if (widget.isQuickAccess && index == 0) {
                                            _navigateBack();
                                          } else {
                                            setState(() {
                                              _currentPath.removeRange(index + 1, _currentPath.length);
                                            });
                                          }
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        child: Text(
                                          displayName,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            color: isLast ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            fontWeight: isLast ? FontWeight.bold : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        if (_currentPath.length > 1)
                          Consumer(
                            builder: (context, ref, child) {
                              final currentFolder = _currentPath.last;
                              final folders = ref.watch(foldersProvider).valueOrNull ?? [];
                              final folder = folders.firstWhere(
                                (f) => f.name == currentFolder, 
                                orElse: () => const FolderItem(name: '', path: '', count: 0, containsMovies: false)
                              );
                              
                              if (folder.path.isEmpty) return const SizedBox.shrink();
                              
                              final isPinned = ref.watch(pinnedFoldersProvider).contains(folder.path);
                              return Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: VeilButton(
                                  type: VeilButtonType.icon,
                                  icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                  onTap: () {
                                    ref.read(pinnedFoldersProvider.notifier).togglePin(folder.path);
                                    HapticFeedback.lightImpact();
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(isPinned ? 'Unpinned from Quick Access' : 'Pinned to Quick Access'),
                                        backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFF3F4F6),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                }
              ),

              Divider(color: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFE5E7EB), height: 1),

              // Content rendering area
              Expanded(
                child: currentFolder == 'root'
                    ? _buildFoldersRoot(theme)
                    : _buildFolderContents(theme, currentFolder, crossAxisCount),
              ),

              // Floating / persistent Clipboard Bar
              FileClipboardBar(
                currentFolderName: currentFolder,
                bottomPadding: widget.isQuickAccess ? 0 : 80,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFoldersRoot(ThemeData theme) {
    final foldersAsync = ref.watch(foldersProvider);

    return foldersAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 1.5),
      ),
      error: (err, stack) => Center(
        child: Text(
          'Error loading folders: $err',
          style: const TextStyle(color: Colors.redAccent),
        ),
      ),
      data: (folders) {
        if (folders.isEmpty) {
          return const VeilEmptyState(
            icon: Icons.folder_off_outlined,
            title: 'No folders detected',
            description: 'Folders containing offline video files will appear here.',
          );
        }

        final history = ref.watch(playbackHistoryProvider);
        final lastWatchedVideoPath = history.isNotEmpty ? history.first.path : null;

        // Find the single best-matching folder for the last-watched video
        final lastWatchedFolder = FolderItem.findLastWatchedFolder(
          folders,
          lastWatchedVideoPath,
        );

        final pinnedPaths = ref.watch(pinnedFoldersProvider);
        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 120.0),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            final isPinned = pinnedPaths.contains(folder.path);
            final isLastWatched = folder == lastWatchedFolder;
            
            return _FolderListTile(
              folder: folder,
              isPinned: isPinned,
              isLastWatched: isLastWatched,
              accentColor: theme.colorScheme.primary,
              onTap: () => _navigateToFolder(folder.name),
              onLongPress: () {
                showFolderActionsBottomSheet(
                  context: context,
                  ref: ref,
                  folder: folder,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFolderContents(ThemeData theme, String folderName, int crossAxisCount) {
    final videoState = ref.watch(folderVideosProvider(folderName));

    if (videoState.videos.isEmpty && !videoState.isLoading) {
      return const VeilEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Empty Folder',
        description: 'This folder contains no playable video files.',
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Video Files Grid
        SliverPadding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final video = videoState.videos[index];
                return Consumer(
                  builder: (context, ref, child) {
                    final thumbnailAsync = ref.watch(videoThumbnailProvider(video));
                    final isSelectionMode = ref.watch(selectionModeProvider);
                    final isSelected = ref.watch(selectedVideosProvider).contains(video.id);
                    final history = ref.watch(playbackHistoryProvider);
                    final lastWatchedItem = history.isNotEmpty ? history.first : null;
                    final isLastWatched = lastWatchedItem != null && (
                      video.id == lastWatchedItem.id ||
                      video.path.replaceAll('\\', '/').toLowerCase() == lastWatchedItem.path.replaceAll('\\', '/').toLowerCase()
                    );

                    return RepaintBoundary(
                      child: Stack(
                        children: [
                          VeilCard(
                            title: video.title,
                            duration: video.formattedDuration,
                            size: video.formattedSize,
                            imagePath: thumbnailAsync.value,
                            isWatched: video.isWatched,
                            isLastWatched: isLastWatched,
                            onTap: () {
                              if (isSelectionMode) {
                                ref.read(selectedVideosProvider.notifier).toggle(video.id);
                              } else {
                                Navigator.push(
                                  context,
                                  VeilPageRoute(
                                    builder: (_) => PlayerScreen(video: video),
                                  ),
                                ).then((_) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    ref.invalidate(playbackHistoryProvider);
                                    ref.invalidate(folderVideosProvider(folderName));
                                    ref.invalidate(foldersProvider);
                                  });
                                });
                              }
                            },
                            onLongPress: () {
                              HapticFeedback.lightImpact();
                              showVideoActionsBottomSheet(
                                context: context,
                                ref: ref,
                                video: video,
                                currentFolderName: folderName,
                              );
                            },
                          ),
                          if (isSelectionMode)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                                        : (theme.brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4)),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected 
                                      ? Align(
                                          alignment: Alignment.topRight,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              childCount: videoState.videos.length,
            ),
          ),
        ),

        if (videoState.isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 1.5),
              ),
            ),
          ),

        // Bottom clearance spacing to clear the floating tab pill bar
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }
}

// Custom Premium Folder List Tile widget with micro scale-highlight tap feedback
class _FolderListTile extends StatefulWidget {
  final FolderItem folder;
  final bool isPinned;
  final bool isLastWatched;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FolderListTile({
    required this.folder,
    required this.isPinned,
    this.isLastWatched = false,
    required this.accentColor,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_FolderListTile> createState() => _FolderListTileState();
}

class _FolderListTileState extends State<_FolderListTile> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: VeilMotion.fast,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
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
    return GestureDetector(
      onTapDown: (_) {
        _animController.forward();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        _animController.reverse();
        setState(() => _isPressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () {
        _animController.reverse();
        setState(() => _isPressed = false);
      },
      onLongPress: () {
        _animController.reverse();
        setState(() => _isPressed = false);
        HapticFeedback.mediumImpact();
        widget.onLongPress();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: VeilMotion.fast,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _isPressed
                ? (theme.brightness == Brightness.dark ? const Color(0xFF0F0F0F) : const Color(0xFFE5E7EB))
                : (widget.isLastWatched 
                    ? widget.accentColor.withValues(alpha: 0.08)
                    : (theme.brightness == Brightness.dark ? const Color(0xFF070707) : const Color(0xFFF3F4F6))),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isLastWatched 
                  ? widget.accentColor 
                  : (_isPressed ? widget.accentColor.withValues(alpha: 0.25) : (theme.brightness == Brightness.dark ? const Color(0xFF131313) : const Color(0xFFE5E7EB))),
              width: widget.isLastWatched ? 1.5 : 1.0,
            ),
            boxShadow: widget.isLastWatched
                ? [BoxShadow(color: widget.accentColor.withValues(alpha: 0.18), blurRadius: 10, spreadRadius: 1)]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.isLastWatched 
                    ? Icons.play_circle_fill_rounded 
                    : (widget.isPinned ? Icons.push_pin_rounded : Icons.folder_open_rounded),
                color: widget.isLastWatched ? widget.accentColor : (widget.isPinned ? widget.accentColor : theme.colorScheme.onSurface),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isLastWatched ? widget.accentColor : theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: widget.isLastWatched ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isLastWatched) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, color: widget.accentColor, size: 10),
                      const SizedBox(width: 2),
                      Text(
                        'LAST PLAYED',
                        style: TextStyle(
                          color: widget.accentColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '${widget.folder.count} videos',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: widget.isLastWatched ? widget.accentColor.withValues(alpha: 0.6) : theme.colorScheme.onSurface.withValues(alpha: 0.24),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
