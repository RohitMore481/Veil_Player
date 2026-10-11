import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/providers/active_video_provider.dart';
import '../providers/audio_player_provider.dart';
import '../screens/now_playing_screen.dart';
import 'audio_queue_sheet.dart';

class AudioMiniPlayer extends ConsumerWidget {
  const AudioMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hide mini-player if full-screen video is currently active
    final activeVideo = ref.watch(activeVideoProvider);
    if (activeVideo != null) {
      return const SizedBox.shrink();
    }

    final queueState = ref.watch(audioPlayerProvider);
    final currentTrack = queueState.currentTrack;

    if (currentTrack == null || queueState.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final progress = (queueState.duration.inMilliseconds > 0)
        ? (queueState.position.inMilliseconds / queueState.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, anim, secAnim) => const NowPlayingScreen(),
            transitionsBuilder: (context, anim, secAnim, child) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
              return SlideTransition(
                position: Tween<Offset>(begin: begin, end: end).animate(curve),
                child: child,
              );
            },
          ),
        );
      },
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121417).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            children: [
              // Thin progress indicator on top
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                minHeight: 2.5,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // Artwork / Avatar icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Track Metadata
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentTrack.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentTrack.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Controls
                      IconButton(
                        icon: Icon(
                          Icons.queue_music_rounded,
                          color: isDark ? Colors.white70 : Colors.black54,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Queue',
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const AudioQueueSheet(),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: queueState.isLoading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : Icon(
                                queueState.isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: theme.colorScheme.primary,
                                size: 34,
                              ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: queueState.isLoading
                            ? null
                            : () {
                                ref.read(audioPlayerProvider.notifier).togglePlayPause();
                              },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: isDark ? Colors.white70 : Colors.black54,
                          size: 28,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          ref.read(audioPlayerProvider.notifier).next();
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
    );
  }
}
