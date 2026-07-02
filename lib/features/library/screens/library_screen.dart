import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_button.dart';
import '../../../core/utils/page_transitions.dart';
import '../../folders/screens/folder_browser_screen.dart';
import '../../player/screens/player_screen.dart';
import '../models/video_item.dart';
import '../providers/media_provider.dart';
import '../widgets/library_bottom_sheets.dart';
import 'search_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  IconData _getFolderIcon(FolderItem folder, List<String> pinnedPaths) {
    if (pinnedPaths.contains(folder.path)) return Icons.push_pin_rounded;
    final lower = folder.name.toLowerCase();
    if (lower.contains('download')) return Icons.download_rounded;
    if (lower.contains('telegram')) return Icons.telegram_rounded;
    if (lower.contains('whatsapp')) return Icons.video_library_rounded;
    if (folder.containsMovies ||
        lower.contains('movie') ||
        lower.contains('film') ||
        lower.contains('cinema')) {
      return Icons.movie_rounded;
    }
    if (lower.contains('show') || lower.contains('series')) {
      return Icons.tv_rounded;
    }
    if (lower.contains('camera') || lower.contains('dcim')) {
      return Icons.photo_camera_back_rounded;
    }
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
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: theme.colorScheme.primary,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Access to Media Required',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Veil Player is an offline-first video player. We need permission to discover and play video files stored on your device.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (permission == 'denied')
                  VeilButton(
                    label: 'Grant Media Permission',
                    icon: Icons.key_rounded,
                    onTap: () {
                      ref.read(permissionProvider.notifier).requestPermission();
                    },
                  )
                else ...[
                  VeilButton(
                    label: 'Open App Settings',
                    icon: Icons.settings_outlined,
                    onTap: () {
                      ref.read(permissionProvider.notifier).openSettings();
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Permissions are permanently denied. Please enable them in system settings to use the player.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
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
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top Header Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'VEIL',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: theme.colorScheme.primary,
                        fontSize: 26,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.search_rounded,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
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
                                  await ref
                                      .read(storageManagerProvider.notifier)
                                      .request();
                                  // Recheck after returning from settings
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
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.7,
                                    )
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.3,
                                    ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.06,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
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
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.5,
                            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue Watching',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
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
                            info:
                                'Resume position • ${_formatDuration(latest.positionMs)}',
                            remaining: latest.remainingTime,
                            progress: latest.progress,
                          );
                        },
                      ),
                    ] else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 28,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFF070707)
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? const Color(0xFF131313)
                                : const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.play_circle_outline_rounded,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.1,
                              ),
                              size: 44,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Videos you start playing will appear here',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
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
                padding: const EdgeInsets.only(
                  top: 24.0,
                  left: 16.0,
                  right: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Access',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    foldersAsync.when(
                      loading: () => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                            strokeWidth: 1.5,
                          ),
                        ),
                      ),
                      error: (err, stack) => Text(
                        'Failed to load folders: $err',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                      data: (folders) {
                        if (folders.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No folders containing videos detected',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.38,
                                ),
                                fontSize: 13,
                              ),
                            ),
                          );
                        }
                        final pinnedPaths = ref.watch(pinnedFoldersProvider);
                        return Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: folders.map((folder) {
                            return _QuickAccessChip(
                              folder: folder,
                              icon: _getFolderIcon(folder, pinnedPaths),
                              accentColor: theme.colorScheme.primary,
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Spacer clearance at bottom
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

class _HeroContinueCard extends StatefulWidget {
  final VideoItem video;
  final String title;
  final String info;
  final String remaining;
  final double progress;

  const _HeroContinueCard({
    required this.video,
    required this.title,
    required this.info,
    required this.remaining,
    required this.progress,
  });

  @override
  State<_HeroContinueCard> createState() => _HeroContinueCardState();
}

class _HeroContinueCardState extends State<_HeroContinueCard>
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
          VeilPageRoute(builder: (_) => PlayerScreen(video: widget.video)),
        );
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
                      : (theme.brightness == Brightness.dark
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFE5E7EB)),
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
                        final thumbnailAsync = ref.watch(
                          videoThumbnailProvider(widget.video),
                        );
                        return Container(
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFF070707)
                              : const Color(0xFFF3F4F6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              thumbnailAsync.when(
                                data: (path) {
                                  if (path != null) {
                                    return Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) =>
                                          const _PlaceholderIcon(),
                                    );
                                  }
                                  return const _PlaceholderIcon();
                                },
                                loading: () => Center(
                                  child: CircularProgressIndicator(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    strokeWidth: 1.5,
                                  ),
                                ),
                                error: (err, stack) => const _PlaceholderIcon(),
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
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
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
                                builder: (_) =>
                                    PlayerScreen(video: widget.video),
                              ),
                            );
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

  const _QuickAccessChip({
    required this.folder,
    required this.icon,
    required this.accentColor,
  });

  @override
  ConsumerState<_QuickAccessChip> createState() => _QuickAccessChipState();
}

class _QuickAccessChipState extends ConsumerState<_QuickAccessChip>
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
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
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
            builder: (_) =>
                FolderBrowserScreen(initialFolder: widget.folder.name),
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
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF0A0A0A)
                  : const Color(0xFFF3F4F6),
              border: Border.all(
                color: _isPressed
                    ? widget.accentColor.withValues(alpha: 0.3)
                    : (theme.brightness == Brightness.dark
                          ? const Color(0xFF161616)
                          : const Color(0xFFE5E7EB)),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: widget.accentColor, size: 15),
                const SizedBox(width: 8),
                Text(
                  widget.folder.name,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
