import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../../../core/utils/page_transitions.dart';
import '../../folders/screens/folder_browser_screen.dart';
import '../../player/screens/player_screen.dart';
import '../models/video_item.dart';
import '../providers/media_provider.dart';
import '../widgets/library_bottom_sheets.dart';
import '../../folders/widgets/manage_pinned_folders_dialog.dart';
import '../../file_operations/widgets/file_clipboard_bar.dart';
import '../../main/widgets/media_section_switcher.dart';
import 'search_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final perm = ref.read(permissionProvider);
        if (perm == 'denied') {
          ref.read(permissionProvider.notifier).requestPermission();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionProvider.notifier).checkPermission();
      ref.read(storageManagerProvider.notifier).recheck();
    }
  }

  IconData _getFolderIcon(FolderItem folder, List<String> pinnedPaths) {
    if (pinnedPaths.contains(folder.path)) return Icons.push_pin_rounded;
    final lower = folder.name.toLowerCase();
    if (lower.contains('download')) return Icons.download_rounded;
    if (lower.contains('telegram')) return Icons.telegram_rounded;
    if (lower.contains('whatsapp')) return Icons.video_library_rounded;
    if (folder.containsMovies || lower.contains('movie') || lower.contains('film') || lower.contains('cinema')) return Icons.movie_rounded;
    if (lower.contains('show') || lower.contains('series')) return Icons.tv_rounded;
    if (lower.contains('camera') || lower.contains('dcim')) return Icons.photo_camera_back_rounded;
    return Icons.folder_rounded;
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minStr:$secStr';
    }
    return '$minStr:$secStr';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final permission = ref.watch(permissionProvider);

    // 1. Loading state
    if (permission == 'checking') {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    // 2. Permission Denied Fallback UI
    if (permission == 'denied' || permission == 'permanently_denied') {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: VeilEmptyState(
            icon: Icons.shield_outlined,
            title: 'Storage Access Required',
            description: 'Allow media access to discover and play video files stored on your device.',
            buttonLabel: permission == 'denied' ? 'Grant Media Permission' : 'Open App Settings',
            buttonIcon: permission == 'denied' ? Icons.key_rounded : Icons.settings_outlined,
            onButtonTap: () {
              if (permission == 'denied') {
                ref.read(permissionProvider.notifier).requestPermission();
              } else {
                ref.read(permissionProvider.notifier).openSettings();
              }
            },
          ),
        ),
      );
    }

    // 3. Normal Authorized UI
    final history = ref.watch(playbackHistoryProvider);
    final foldersAsync = ref.watch(foldersProvider);
    final isStorageManager = ref.watch(storageManagerProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Row 1: Shared App Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 14.0, 16.0, 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0), // Nudge right for optical alignment
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            size: 24,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              VeilPageRoute(
                                builder: (_) => const SearchScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        // Storage Manager permission indicator — tappable
                        GestureDetector(
                          onTap: isStorageManager
                              ? null
                              : () async {
                                  await ref.read(storageManagerProvider.notifier).request();
                                  // Recheck after returning from settings
                                  await ref.read(storageManagerProvider.notifier).recheck();
                                },
                          child: Tooltip(
                            message: isStorageManager
                                ? 'Full storage access granted — silent file operations active'
                                : 'Tap to enable silent file operations (no system dialogs)',
                            child: Icon(
                              isStorageManager ? Icons.shield_rounded : Icons.shield_outlined,
                              color: isStorageManager
                                  ? theme.colorScheme.primary.withValues(alpha: 0.7)
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
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

            // Row 2: Media Section Switcher
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.0, 0, 16.0, 14.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MediaSectionSwitcher(),
                ),
              ),
            ),

            // Storage Manager Permission Banner (shown only when not granted)
            if (!isStorageManager)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: GestureDetector(
                    onTap: () async {
                      await ref.read(storageManagerProvider.notifier).request();
                      await ref.read(storageManagerProvider.notifier).recheck();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: theme.colorScheme.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Enable silent file operations — tap to grant full storage access',
                              style: TextStyle(
                                color: theme.colorScheme.primary.withValues(alpha: 0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // SECTION 1: Continue Watching Hero
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue Watching',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (history.isNotEmpty) ...[
                      Builder(
                        builder: (context) {
                          final latest = history.first;
                          
                          // Extract parent folder name from path
                          String folderName = 'Storage';
                          final normalized = latest.path.replaceAll('\\', '/');
                          final parts = normalized.split('/');
                          if (parts.length > 1) {
                            folderName = parts[parts.length - 2];
                          }

                          // Map back to a clean VideoItem for playback controller compatibility
                          final videoItem = VideoItem(
                            id: latest.id,
                            title: latest.title,
                            path: latest.path,
                            duration: Duration(milliseconds: latest.durationMs),
                            size: 0,
                            dateAdded: DateTime.now(),
                            folderName: folderName,
                          );

                          return _HeroContinueCard(
                            video: videoItem,
                            title: latest.title,
                            info: 'Resume position • ${_formatDuration(latest.positionMs)}',
                            remaining: latest.remainingTime,
                            progress: latest.progress,
                            positionMs: latest.positionMs,
                            durationMs: latest.durationMs,
                          );
                        },
                      ),
                    ] else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark ? const Color(0xFF070707) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark ? const Color(0xFF131313) : const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.play_circle_outline_rounded,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                              size: 44,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Videos you start playing will appear here',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // SECTION 2: Quick Access (Folders)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24.0, left: 16.0, right: 16.0),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (ref.watch(pinnedFoldersProvider).isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => const ManagePinnedFoldersDialog(),
                              );
                            },
                            child: Text(
                              'Manage',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
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
                          child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 1.5),
                        ),
                      ),
                      error: (err, stack) => Text(
                        'Failed to load folders: $err',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      data: (folders) {
                        final pinnedPaths = ref.watch(pinnedFoldersProvider);
                        final history = ref.watch(playbackHistoryProvider);
                        final lastWatchedVideoPath = history.isNotEmpty ? history.first.path : null;

                        final quickAccessFolders = folders.where((f) {
                          if (pinnedPaths.contains(f.path)) return true;
                          final nameLower = f.name.toLowerCase();
                          return nameLower == 'camera' || 
                                 nameLower == 'dcim' || 
                                 nameLower == 'telegram video' || 
                                 nameLower == 'whatsapp video' || 
                                 nameLower == 'download' || 
                                 nameLower == 'downloads' || 
                                 nameLower == 'movies' || 
                                 f.containsMovies;
                        }).toList();

                        if (quickAccessFolders.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No folders containing videos detected',
                              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 13),
                            ),
                          );
                        }

                        // Find the single best-matching folder for the last-watched video
                        final lastWatchedFolder = FolderItem.findLastWatchedFolder(
                          quickAccessFolders,
                          lastWatchedVideoPath,
                        );
                        
                        return Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: quickAccessFolders.map((folder) {
                            final isLastWatched = folder == lastWatchedFolder;
                            return _QuickAccessChip(
                              folder: folder,
                              icon: _getFolderIcon(folder, pinnedPaths),
                              accentColor: theme.colorScheme.primary,
                              isLastWatched: isLastWatched,
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Spacer clearance at bottom (clears floating nav bar & mini-player)
            const SliverToBoxAdapter(
              child: SizedBox(height: 160),
            ),
          ],
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: FileClipboardBar(bottomPadding: 80),
        ),
      ],
    ),
  ),
);
  }
}

class _HeroContinueCard extends ConsumerStatefulWidget {
  final VideoItem video;
  final String title;
  final String info;
  final String remaining;
  final double progress;
  final int positionMs;
  final int durationMs;

  const _HeroContinueCard({
    required this.video,
    required this.title,
    required this.info,
    required this.remaining,
    required this.progress,
    required this.positionMs,
    required this.durationMs,
  });

  @override
  ConsumerState<_HeroContinueCard> createState() => _HeroContinueCardState();
}

class _HeroContinueCardState extends ConsumerState<_HeroContinueCard> with SingleTickerProviderStateMixin {
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

    return GestureDetector(
      onTapDown: (_) {
        _animController.forward();
        setState(() => _isHighlighted = true);
      },
      onTapUp: (_) {
        _animController.reverse();
        setState(() => _isHighlighted = false);
        Navigator.push(
          context,
          VeilPageRoute(
            builder: (_) => PlayerScreen(video: widget.video),
          ),
        ).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.invalidate(playbackHistoryProvider);
            ref.invalidate(foldersProvider);
          });
        });
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
                      ? theme.colorScheme.primary.withValues(alpha: 0.3)
                      : (theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB)), 
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Consumer(
                      builder: (context, ref, child) {
                        final thumbnailAsync = ref.watch(videoThumbnailProvider(widget.video));
                        return Container(
                          color: theme.brightness == Brightness.dark ? const Color(0xFF070707) : const Color(0xFFF3F4F6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              thumbnailAsync.when(
                                data: (path) {
                                  if (path != null) {
                                    return Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) => const _PlaceholderIcon(),
                                    );
                                  }
                                  return const _PlaceholderIcon();
                                },
                                loading: () => Center(
                                  child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 1.5),
                                ),
                                error: (err, stack) => const _PlaceholderIcon(),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () {
                                    showContinueWatchingInfoSheet(
                                      context: context,
                                      ref: ref,
                                      video: widget.video,
                                      positionMs: widget.positionMs,
                                      durationMs: widget.durationMs,
                                      progress: widget.progress,
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.info_outline_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: FractionallySizedBox(
                                  alignment: Alignment.bottomLeft,
                                  widthFactor: widget.progress.clamp(0.0, 1.0),
                                  child: Container(
                                    height: 3.5,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.info,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        VeilButton(
                          height: 36,
                          label: 'Continue',
                          icon: Icons.play_arrow_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              VeilPageRoute(
                                builder: (_) => PlayerScreen(video: widget.video),
                              ),
                            ).then((_) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                ref.invalidate(playbackHistoryProvider);
                                ref.invalidate(foldersProvider);
                              });
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Icon(
        Icons.movie_filter_outlined,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        size: 56,
      ),
    );
  }
}

class _QuickAccessChip extends ConsumerStatefulWidget {
  final FolderItem folder;
  final IconData icon;
  final Color accentColor;
  final bool isLastWatched;

  const _QuickAccessChip({
    required this.folder,
    required this.icon,
    required this.accentColor,
    this.isLastWatched = false,
  });

  @override
  ConsumerState<_QuickAccessChip> createState() => _QuickAccessChipState();
}

class _QuickAccessChipState extends ConsumerState<_QuickAccessChip> with SingleTickerProviderStateMixin {
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
            builder: (_) => FolderBrowserScreen(
              initialFolder: widget.folder.name,
              isQuickAccess: true,
            ),
          ),
        );
      },
      onTapCancel: () {
        _animController.reverse();
        setState(() => _isPressed = false);
      },
      onLongPress: () {
        _animController.reverse();
        setState(() => _isPressed = false);
        HapticFeedback.mediumImpact();
        showFolderActionsBottomSheet(
          context: context,
          ref: ref,
          folder: widget.folder,
        );
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: _isPressed ? 0.75 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isLastWatched
                  ? widget.accentColor.withValues(alpha: 0.12)
                  : (theme.brightness == Brightness.dark ? const Color(0xFF0A0A0A) : const Color(0xFFF3F4F6)),
              border: Border.all(
                color: _isPressed 
                  ? widget.accentColor.withValues(alpha: 0.5) 
                  : (widget.isLastWatched 
                      ? widget.accentColor 
                      : (theme.brightness == Brightness.dark ? const Color(0xFF161616) : const Color(0xFFE5E7EB))),
                width: widget.isLastWatched ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.isLastWatched && !_isPressed
                  ? [BoxShadow(color: widget.accentColor.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 1)]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isLastWatched ? Icons.play_circle_fill_rounded : widget.icon,
                  color: widget.accentColor,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.folder.name,
                  style: TextStyle(
                    color: widget.isLastWatched ? widget.accentColor : theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: widget.isLastWatched ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.folder.count}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 10,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                if (widget.folder.newVideosCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.folder.newVideosCount} New',
                      style: TextStyle(
                        color: widget.accentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
