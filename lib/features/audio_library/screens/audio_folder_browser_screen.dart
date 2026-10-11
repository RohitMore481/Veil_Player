import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/veil_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../models/audio_folder_item.dart';
import '../providers/audio_library_providers.dart';
import '../providers/audio_pinned_folders_provider.dart';
import '../providers/audio_player_provider.dart';
import 'audio_folder_detail_screen.dart';

class AudioFolderBrowserScreen extends ConsumerStatefulWidget {
  final String? initialFolder;
  final bool isQuickAccess;

  const AudioFolderBrowserScreen({
    super.key,
    this.initialFolder,
    this.isQuickAccess = false,
  });

  @override
  ConsumerState<AudioFolderBrowserScreen> createState() =>
      _AudioFolderBrowserScreenState();
}

class _AudioFolderBrowserScreenState
    extends ConsumerState<AudioFolderBrowserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.initialFolder != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final folders = ref.read(audioFoldersProvider).valueOrNull ?? [];
        final match = folders.cast<AudioFolderItem?>().firstWhere(
              (f) => f?.name == widget.initialFolder,
              orElse: () => null,
            );
        if (match != null && mounted) {
          Navigator.push(
            context,
            VeilPageRoute(
              builder: (_) => AudioFolderDetailScreen(folder: match),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final foldersAsync = ref.watch(audioFoldersProvider);
    final pinnedPaths = ref.watch(audioPinnedFoldersProvider);
    final recentTracks = ref.watch(recentlyPlayedAudioProvider);
    final lastPlayedTrack =
        recentTracks.isNotEmpty ? recentTracks.first : null;

    final canGoBack = widget.isQuickAccess || Navigator.canPop(context);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Navigation Header Bar (Consistent with Video FolderBrowserScreen)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: canGoBack ? 8.0 : 16.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  if (canGoBack) ...[
                    VeilButton(
                      type: VeilButtonType.icon,
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.isQuickAccess ? 'Quick Access' : 'Storage',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    tooltip: 'Rescan Folders',
                    onPressed: () {
                      ref.invalidate(audioFoldersProvider);
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

            // Content Area
            Expanded(
              child: foldersAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: primary,
                    strokeWidth: 1.5,
                  ),
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
                      title: 'No audio folders detected',
                      description:
                          'Folders containing offline audio tracks will appear here.',
                    );
                  }

                  // Determine last-played folder
                  AudioFolderItem? lastPlayedFolder;
                  if (lastPlayedTrack != null) {
                    for (final f in folders) {
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

                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 12.0,
                      bottom: 120.0,
                    ),
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final isPinned = pinnedPaths.contains(folder.path);
                      final isLastPlayed = folder == lastPlayedFolder;

                      return _AudioFolderListTile(
                        folder: folder,
                        isPinned: isPinned,
                        isLastPlayed: isLastPlayed,
                        accentColor: primary,
                        onTap: () {
                          Navigator.push(
                            context,
                            VeilPageRoute(
                              builder: (_) =>
                                  AudioFolderDetailScreen(folder: folder),
                            ),
                          );
                        },
                        onLongPress: () {
                          _showAudioFolderBottomSheet(
                            context,
                            ref,
                            folder,
                            isPinned,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioFolderBottomSheet(
    BuildContext context,
    WidgetRef ref,
    AudioFolderItem folder,
    bool isPinned,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14171A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.folder_rounded, color: primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          '${folder.trackCount} songs • ${folder.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            ListTile(
              leading: Icon(Icons.play_arrow_rounded, color: primary),
              title: const Text('Play Folder'),
              onTap: () async {
                Navigator.pop(ctx);
                final repo = ref.read(audioMediaRepositoryProvider);
                final tracks = await repo.getAudioTracks(
                  limit: 1000,
                  offset: 0,
                  folderPath: folder.path,
                );
                if (tracks.isNotEmpty) {
                  ref
                      .read(audioPlayerProvider.notifier)
                      .playTrackList(tracks, initialIndex: 0);
                }
              },
            ),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: isPinned ? primary : (isDark ? Colors.white70 : Colors.black87),
              ),
              title: Text(isPinned ? 'Unpin from Quick Access' : 'Pin to Quick Access'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(audioPinnedFoldersProvider.notifier)
                    .togglePin(folder.path);
                HapticFeedback.lightImpact();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Consistent with Video's _FolderListTile
class _AudioFolderListTile extends StatefulWidget {
  final AudioFolderItem folder;
  final bool isPinned;
  final bool isLastPlayed;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AudioFolderListTile({
    required this.folder,
    required this.isPinned,
    this.isLastPlayed = false,
    required this.accentColor,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_AudioFolderListTile> createState() => _AudioFolderListTileState();
}

class _AudioFolderListTileState extends State<_AudioFolderListTile>
    with SingleTickerProviderStateMixin {
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
                ? (theme.brightness == Brightness.dark
                    ? const Color(0xFF0F0F0F)
                    : const Color(0xFFE5E7EB))
                : (widget.isLastPlayed
                    ? widget.accentColor.withValues(alpha: 0.08)
                    : (theme.brightness == Brightness.dark
                        ? const Color(0xFF070707)
                        : const Color(0xFFF3F4F6))),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isLastPlayed
                  ? widget.accentColor
                  : (_isPressed
                      ? widget.accentColor.withValues(alpha: 0.25)
                      : (theme.brightness == Brightness.dark
                          ? const Color(0xFF131313)
                          : const Color(0xFFE5E7EB))),
              width: widget.isLastPlayed ? 1.5 : 1.0,
            ),
            boxShadow: widget.isLastPlayed
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.18),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.isLastPlayed
                    ? Icons.play_circle_fill_rounded
                    : (widget.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.folder_open_rounded),
                color: widget.isLastPlayed
                    ? widget.accentColor
                    : (widget.isPinned
                        ? widget.accentColor
                        : theme.colorScheme.onSurface),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isLastPlayed
                        ? widget.accentColor
                        : theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight:
                        widget.isLastPlayed ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isLastPlayed) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: widget.accentColor, size: 10),
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
                '${widget.folder.trackCount} songs',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: widget.isLastPlayed
                    ? widget.accentColor.withValues(alpha: 0.6)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.24),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
