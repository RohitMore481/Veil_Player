import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_queue_state.dart';
import '../providers/audio_player_provider.dart';
import '../widgets/audio_queue_sheet.dart';
import '../widgets/sleep_timer_dialog.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final queueState = ref.watch(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final currentTrack = queueState.currentTrack;

    if (currentTrack == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text(
            'No track currently playing',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
      );
    }

    final duration = queueState.duration;
    final position = _dragValue != null
        ? Duration(milliseconds: _dragValue!.toInt())
        : queueState.position;

    final totalMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Top Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: primary,
                    ),
                  ),
                  IconButton(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.queue_music_rounded, color: Colors.white70),
                        if (queueState.queue.isNotEmpty)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${queueState.queue.length}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => const AudioQueueSheet(),
                      );
                    },
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // Album Artwork
              Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.76,
                  height: MediaQuery.of(context).size.width * 0.76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.15),
                        blurRadius: 36,
                        spreadRadius: 2,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildArtworkWidget(currentTrack.albumArtUri, primary),
                ),
              ),
              const Spacer(flex: 1),

              // Track Title & Artist
              Column(
                children: [
                  Text(
                    currentTrack.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${currentTrack.artist}  •  ${currentTrack.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Error banner if any
              if (queueState.errorMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    queueState.errorMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),

              // Seek Bar & Time Labels
              Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: primary,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: primary,
                      overlayColor: primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: posMs,
                      min: 0.0,
                      max: totalMs > 0 ? totalMs : 1.0,
                      onChanged: (val) {
                        setState(() {
                          _dragValue = val;
                        });
                      },
                      onChangeEnd: (val) {
                        notifier.seek(Duration(milliseconds: val.toInt()));
                        setState(() {
                          _dragValue = null;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Playback Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Shuffle Button
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: queueState.isShuffleEnabled ? primary : Colors.white38,
                      size: 24,
                    ),
                    onPressed: () {
                      notifier.toggleShuffle();
                    },
                  ),

                  // Previous Button
                  IconButton(
                    icon: const Icon(
                      Icons.skip_previous_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                    onPressed: () {
                      notifier.previous();
                    },
                  ),

                  // Play/Pause Floating Action Button
                  GestureDetector(
                    onTap: queueState.isLoading
                        ? null
                        : () {
                            notifier.togglePlayPause();
                          },
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: queueState.isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              ),
                            )
                          : Icon(
                              queueState.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 40,
                            ),
                    ),
                  ),

                  // Next Button
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                    onPressed: () {
                      notifier.next();
                    },
                  ),

                  // Repeat Button
                  IconButton(
                    icon: Icon(
                      switch (queueState.repeatMode) {
                        AudioRepeatMode.one => Icons.repeat_one_rounded,
                        AudioRepeatMode.all => Icons.repeat_rounded,
                        AudioRepeatMode.off => Icons.repeat_rounded,
                      },
                      color: queueState.repeatMode != AudioRepeatMode.off
                          ? primary
                          : Colors.white38,
                      size: 24,
                    ),
                    onPressed: () {
                      notifier.cycleRepeatMode();
                    },
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // Bottom Actions (Sleep timer indicator & sheet)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: Icon(
                        Icons.bedtime_outlined,
                        size: 18,
                        color: notifier.isSleepTimerActive ? primary : Colors.white54,
                      ),
                      label: Text(
                        notifier.isSleepTimerActive
                            ? 'Sleep Timer: ${notifier.activeSleepTimerLabel}'
                            : 'Sleep Timer',
                        style: TextStyle(
                          fontSize: 13,
                          color: notifier.isSleepTimerActive ? primary : Colors.white54,
                          fontWeight: notifier.isSleepTimerActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) => const SleepTimerSheet(),
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
    );
  }

  Widget _buildArtworkWidget(String? artUri, Color primary) {
    if (artUri != null && artUri.isNotEmpty) {
      if (artUri.startsWith('content://')) {
        // MediaStore content URI for album art
        return Image.network(
          artUri,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildFallbackArtwork(primary),
        );
      } else if (File(artUri).existsSync()) {
        return Image.file(
          File(artUri),
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildFallbackArtwork(primary),
        );
      }
    }
    return _buildFallbackArtwork(primary);
  }

  Widget _buildFallbackArtwork(Color primary) {
    return Container(
      color: const Color(0xFF14171A),
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 110,
          color: primary.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minStr:$secStr';
    }
    return '$minStr:$secStr';
  }
}
