import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/widgets/veil_slider.dart';
import '../../../core/widgets/veil_button.dart';
import '../../../core/theme/veil_theme.dart';
import '../../library/models/video_item.dart';
import '../../library/services/media_service.dart';
import '../../library/providers/media_provider.dart';
import '../../media_capabilities/models/playback_error.dart';
import '../../media_capabilities/providers/media_capabilities_provider.dart';
import '../widgets/brightness_volume_overlay.dart';
import '../widgets/player_menu_sheets.dart';
import '../widgets/speed_overlay.dart';
import '../widgets/double_tap_ripple.dart';
import '../widgets/seek_gesture_overlay.dart';
import '../providers/player_settings_provider.dart';
import '../widgets/folder_queue_panel.dart';
import 'package:veil_player/core/utils/crash_handler.dart';
import 'package:veil_player/core/utils/method_channel_dispatcher.dart';
import 'package:veil_player/features/player/providers/active_video_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final VideoItem? video;
  const PlayerScreen({super.key, this.video});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;

  VideoItem? get _activeVideo => _currentVideo;

  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // UI state
  bool showControls = true;
  bool speedBoostActive = false;
  bool isLocked = false;
  bool showQueuePanel = false;

  // HUD states for swipe gestures
  double volumeValue = 0.5;
  double brightnessValue = 0.5;
  bool showVolumeHUD = false;
  bool showBrightnessHUD = false;

  // HUD state for general notifications (Aspect ratio / Orientation)
  String? hudNotificationText;
  IconData? hudNotificationIcon;
  Timer? hudNotificationTimer;

  // Double tap ripples
  bool showDoubleTapRippleLeft = false;
  bool showDoubleTapRippleRight = false;

  // Horizontal seek gesture state
  bool isDraggingSeek = false;
  double dragSecondsAccumulator = 0.0;
  Duration targetSeekPosition = Duration.zero;
  int seekDeltaSeconds = 0;

  // Scrubber drag state
  bool isDraggingScrubber = false;
  double scrubberDragValue = 0.0;
  bool _pausedForAudioFocus = false;

  // Sleep timer state
  String activeSleepTimer = 'Off';
  Duration? sleepTimerRemaining;
  Timer? sleepTimer;

  // Resume playback dialog
  bool showResumeDialog = false;
  int savedProgressMs = 0;

  // Orientation state
  String orientationMode = 'Auto';

  List<SubtitleTrack> subtitleTracks = [];
  List<SubtitleTrack> discoveredSubtitles = [];
  SubtitleTrack? activeSubtitleTrack;
  StreamSubscription? tracksSub;

  Timer? hideTimer;
  Timer? hudOverlayTimer;

  StreamSubscription? positionSub;
  StreamSubscription? durationSub;
  StreamSubscription? playingSub;
  StreamSubscription? completedSub;
  StreamSubscription? errorSub;

  // Media Capabilities Layer state
  PlaybackError? _currentPlaybackError;
  bool _showPlaybackError = false;

  int lastSavedPositionMs = 0;

  String? _savedSubtitleTrackId;
  String? _savedAudioTrackId;
  bool _hasRestoredTracks = false;
  bool _isInPipMode = false;
  bool _isChangingVideo = false;
  List<VideoItem> _folderVideos = [];
  int _currentIndex = -1;
  bool _isLoadingFolderVideos = false;
  VideoItem? _currentVideo;
  int _activeSubtitleDelayMs = 0;
  int _activeAudioDelayMs = 0;

  void _restoreSavedTracks() {
    if (!mounted || _hasRestoredTracks) return;

    final tracks = player.state.tracks;

    if (tracks.audio.isEmpty &&
        tracks.subtitle.isEmpty &&
        discoveredSubtitles.isEmpty) {
      return;
    }

    bool restoredSub = false;
    bool restoredAudio = false;

    if (_savedSubtitleTrackId != null) {
      final uniqueTracks = <String, SubtitleTrack>{};
      for (final t in tracks.subtitle) {
        uniqueTracks[t.id] = t;
      }
      for (final t in discoveredSubtitles) {
        uniqueTracks[t.id] = t;
      }

      final match = uniqueTracks[_savedSubtitleTrackId];
      if (match != null) {
        player.setSubtitleTrack(match);
        setState(() {
          activeSubtitleTrack = match;
        });
        restoredSub = true;
      }
    } else {
      restoredSub = true;
    }

    if (_savedAudioTrackId != null) {
      final match = tracks.audio.firstWhere(
        (t) => t.id == _savedAudioTrackId,
        orElse: () => const AudioTrack('none', '', ''),
      );
      if (match.id != 'none') {
        player.setAudioTrack(match);
        restoredAudio = true;
      }
    } else {
      restoredAudio = true;
    }

    if (restoredSub && restoredAudio) {
      _hasRestoredTracks = true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentVideo = widget.video;

    final settings = ref.read(playerSettingsProvider);
    player = Player();
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: settings.hwDecoding,
      ),
    );

    _initPlayback();
    _initSettings();

    MethodChannelDispatcher.addListener(_handleMethodCall);
    _updateActiveVideo(_currentVideo);

    tracksSub = player.stream.tracks.listen((tracks) {
      if (!mounted) return;
      _restoreSavedTracks();

      // Update PIP dimensions
      final w = player.state.width ?? 16;
      final h = player.state.height ?? 9;
      MediaService().setPipEnabled(true, numerator: w, denominator: h);

      setState(() {
        subtitleTracks = tracks.subtitle;
        final selected = player.state.track.subtitle;
        activeSubtitleTrack = tracks.subtitle.firstWhere(
          (t) => t.id == selected.id,
          orElse: () => activeSubtitleTrack ?? SubtitleTrack.auto(),
        );
      });
    });

    positionSub = player.stream.position.listen((event) {
      if (!mounted) return;
      setState(() {
        position = event;
      });

      // Save progress periodically (every 5 seconds)
      if (isPlaying &&
          event.inMilliseconds > 0 &&
          (event.inMilliseconds - lastSavedPositionMs).abs() > 5000) {
        _savePosition();
      }

      // Check sleep timer if "End of Video"
      if (activeSleepTimer == 'End of Video' &&
          duration.inMilliseconds > 0 &&
          event.inMilliseconds >= duration.inMilliseconds - 200) {
        _onVideoEnded();
      }
    });

    durationSub = player.stream.duration.listen((event) {
      if (!mounted) return;
      setState(() {
        duration = event;
      });
      _syncMediaSession();
    });

    playingSub = player.stream.playing.listen((event) {
      if (!mounted) return;
      setState(() {
        isPlaying = event;
      });
      if (event) {
        MediaService().requestAudioFocus();
      } else {
        if (!_pausedForAudioFocus) {
          MediaService().abandonAudioFocus();
        }
      }
      _syncMediaSession();
    });

    completedSub = player.stream.completed.listen((completed) async {
      if (!completed ||
          _isChangingVideo ||
          player.state.position.inMilliseconds < 1000) {
        return;
      }

      // 1. If sleep timer is set to "End of Video", prioritize ending video
      if (activeSleepTimer == 'End of Video') {
        _onVideoEnded();
        return;
      }

      // 2. Fetch latest settings
      final settings = ref.read(playerSettingsProvider);

      // 3. Check repeatMode setting
      if (settings.repeatMode == 'one') {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }

      // 4. Check auto-play next
      final hasNext =
          _currentIndex >= 0 && _currentIndex < _folderVideos.length - 1;

      if (settings.autoPlayNext) {
        if (hasNext) {
          final nextVideo = _folderVideos[_currentIndex + 1];
          _loadVideo(nextVideo);
          return;
        } else {
          _onVideoEnded();
          return;
        }
      }

      // If repeatMode is 'folder' and we are at the end, wrap around to the first video
      if (settings.repeatMode == 'folder') {
        if (hasNext) {
          final nextVideo = _folderVideos[_currentIndex + 1];
          _loadVideo(nextVideo);
          return;
        } else if (_folderVideos.isNotEmpty) {
          _loadVideo(_folderVideos.first);
          return;
        }
      }

      _onVideoEnded();
    });

    // ── Media Capabilities: error detection ───────────────────────────────────
    errorSub = player.stream.error.listen((errorMessage) {
      if (!mounted || errorMessage.isEmpty) return;
      final diagnosticsService = ref.read(mediaDiagnosticsServiceProvider);
      final error = diagnosticsService.classifyRawError(errorMessage);
      setState(() {
        _currentPlaybackError = error;
        _showPlaybackError = true;
      });
      // Update the global error provider
      ref.read(currentPlaybackErrorProvider.notifier).state = error;
      // Auto-dismiss the error overlay after 8 seconds
      Timer(const Duration(seconds: 8), () {
        if (mounted) {
          setState(() {
            _showPlaybackError = false;
          });
        }
      });
    });

    // Initialize folder list navigation asynchronously after the first frame
    if (_currentVideo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadFolderVideos(_currentVideo!);
        }
      });
    }

    startHideTimer();
  }

  void _onVideoEnded() {
    player.pause();
    setState(() {
      activeSleepTimer = 'Off';
      sleepTimerRemaining = null;
    });
    sleepTimer?.cancel();
  }

  Future<void> _loadFolderVideos(VideoItem currentVideo) async {
    final stopwatch = Stopwatch()..start();

    if (mounted) {
      setState(() {
        _isLoadingFolderVideos = true;
      });
    }

    final path = currentVideo.path;
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('asset://')) {
      if (mounted) {
        setState(() {
          _folderVideos = [currentVideo];
          _currentIndex = 0;
          _isLoadingFolderVideos = false;
        });
      }
      return;
    }

    List<VideoItem> resolvedVideos = [];
    final parentDir = File(path).absolute.parent;
    final parentPath = parentDir.path;

    try {
      if (await parentDir.exists()) {
        final List<FileSystemEntity> entities = [];
        await for (final entity in parentDir.list(
          recursive: false,
          followLinks: false,
        )) {
          entities.add(entity);
        }

        final supportedExtensions = {
          'mkv',
          'mp4',
          'avi',
          'mov',
          'webm',
          'ts',
          'mts',
          'm2ts',
          'flv',
          '3gp',
          '3g2',
          '3gpp',
          'ogv',
          'wmv',
          'rm',
          'rmvb',
          'mpeg',
          'mpg',
          'vob',
          'm4v',
          'f4v',
        };

        final List<String> filePaths = [];
        for (final entity in entities) {
          if (entity is File) {
            final name = entity.path.split(RegExp(r'[/\\]')).last;
            if (name.startsWith('.')) continue; // ignore hidden
            final ext = name.split('.').last.toLowerCase();
            // ignore subtitle files explicitly
            if (ext == 'srt' ||
                ext == 'vtt' ||
                ext == 'ass' ||
                ext == 'ssa' ||
                ext == 'sub' ||
                ext == 'idx') {
              continue;
            }
            if (supportedExtensions.contains(ext)) {
              filePaths.add(entity.path);
            }
          }
        }

        if (filePaths.isNotEmpty) {
          // Attempt to map using MediaStore query fallback
          try {
            final mediaStoreVideos = await ref
                .read(mediaRepositoryProvider)
                .getVideos(limit: 1000, offset: 0, folderPath: parentPath);
            final mediaMap = {for (var v in mediaStoreVideos) v.path: v};
            for (final filePath in filePaths) {
              final existing = mediaMap[filePath];
              if (existing != null) {
                resolvedVideos.add(existing);
              } else {
                final file = File(filePath);
                final name = filePath.split(RegExp(r'[/\\]')).last;
                final exists = await file.exists();
                final size = exists ? await file.length() : 0;
                final modified = exists
                    ? await file.lastModified()
                    : DateTime.now();
                resolvedVideos.add(
                  VideoItem(
                    id: filePath.hashCode.toString(),
                    title: name,
                    path: filePath,
                    duration: Duration.zero,
                    size: size,
                    dateAdded: modified,
                    folderName: parentPath
                        .split(RegExp(r'[/\\]'))
                        .lastWhere(
                          (s) => s.isNotEmpty,
                          orElse: () => 'Storage',
                        ),
                  ),
                );
              }
            }
          } catch (_) {
            // Standard fallback without MediaStore query
            for (final filePath in filePaths) {
              final file = File(filePath);
              final name = filePath.split(RegExp(r'[/\\]')).last;
              final exists = await file.exists();
              final size = exists ? await file.length() : 0;
              final modified = exists
                  ? await file.lastModified()
                  : DateTime.now();
              resolvedVideos.add(
                VideoItem(
                  id: filePath.hashCode.toString(),
                  title: name,
                  path: filePath,
                  duration: Duration.zero,
                  size: size,
                  dateAdded: modified,
                  folderName: parentPath
                      .split(RegExp(r'[/\\]'))
                      .lastWhere((s) => s.isNotEmpty, orElse: () => 'Storage'),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
        'Physical folder read failed: $e. Falling back to MediaStore query.',
      );
    }

    // Fallback if physical listing returned nothing
    if (resolvedVideos.isEmpty) {
      try {
        final mediaStoreVideos = await ref
            .read(mediaRepositoryProvider)
            .getVideos(limit: 1000, offset: 0, folderPath: parentPath);
        resolvedVideos = mediaStoreVideos;
      } catch (e) {
        debugPrint('MediaStore query fallback failed: $e');
      }
    }

    // Ensure the current video is present
    final hasCurrent = resolvedVideos.any(
      (v) => v.path == currentVideo.path || v.id == currentVideo.id,
    );
    if (!hasCurrent) {
      resolvedVideos.add(currentVideo);
    }

    // Sort using natural sorting
    resolvedVideos.sort((a, b) => _naturalCompare(a.title, b.title));

    final index = resolvedVideos.indexWhere(
      (v) => v.path == currentVideo.path || v.id == currentVideo.id,
    );

    stopwatch.stop();

    if (mounted) {
      setState(() {
        _folderVideos = resolvedVideos;
        _currentIndex = index != -1 ? index : 0;
        _isLoadingFolderVideos = false;
      });
    }
  }

  // Natural Sort alphanumeric comparison helper
  int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final matchesA = regex
        .allMatches(a.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final matchesB = regex
        .allMatches(b.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

    for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
      final matchA = matchesA[i];
      final matchB = matchesB[i];

      final isDigitA = RegExp(r'^\d+$').hasMatch(matchA);
      final isDigitB = RegExp(r'^\d+$').hasMatch(matchB);

      if (isDigitA && isDigitB) {
        final valA = int.parse(matchA);
        final valB = int.parse(matchB);
        if (valA != valB) {
          return valA.compareTo(valB);
        }
      } else {
        final comp = matchA.compareTo(matchB);
        if (comp != 0) {
          return comp;
        }
      }
    }
    return matchesA.length.compareTo(matchesB.length);
  }

  Future<void> _initPlayback() async {
    _isChangingVideo = true;
    try {
      final active = _activeVideo;
      if (active == null) {
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
      final subId = await MediaService().getPlayerSetting(
        '${active.id}_subtitle_track_id',
        'string',
      );
      final audioId = await MediaService().getPlayerSetting(
        '${active.id}_audio_track_id',
        'string',
      );
      final subDelay = await MediaService().getPlayerSetting(
        '${active.id}_subtitle_delay',
        'int',
      );
      final audioDelay = await MediaService().getPlayerSetting(
        '${active.id}_audio_delay',
        'int',
      );
      if (mounted) {
        setState(() {
          _savedSubtitleTrackId = subId as String?;
          _savedAudioTrackId = audioId as String?;
          _activeSubtitleDelayMs = (subDelay as int?) ?? 0;
          _activeAudioDelayMs = (audioDelay as int?) ?? 0;
        });
      }

      final videoPath = active.path;
      await player.open(Media(videoPath), play: false);

      // Fetch and apply initial settings
      final settings = ref.read(playerSettingsProvider);
      _applySettings(settings);

      // Try to discover sidecar subtitles for local files
      if (!videoPath.startsWith('asset://') &&
          !videoPath.startsWith('http://') &&
          !videoPath.startsWith('https://')) {
        _discoverSidecarSubtitles(videoPath).then((sidecars) {
          if (mounted) {
            setState(() {
              discoveredSubtitles = sidecars;
            });
            _restoreSavedTracks();
          }
        });
      }

      if (settings.autoResume) {
        final saved = await MediaService().getPlaybackPosition(active.id);
        if (saved != null) {
          final positionMs = saved['position'] as int;
          final durationMs = saved['duration'] as int;
          if (positionMs > 1000 &&
              durationMs > 0 &&
              (positionMs / durationMs) < 0.95) {
            setState(() {
              showResumeDialog = true;
              savedProgressMs = positionMs;
            });
            return; // Keep paused while dialog is showing
          }
        }
      }

      await player.play();
      if (mounted) {
        setState(() {
          subtitleTracks = player.state.tracks.subtitle;
          activeSubtitleTrack = player.state.track.subtitle;
        });
        MediaService().setPipEnabled(
          true,
          numerator: player.state.width ?? 16,
          denominator: player.state.height ?? 9,
        );
      }
    } finally {
      _isChangingVideo = false;
    }
  }

  void _playNextVideo() {
    final hasNext =
        _currentIndex >= 0 && _currentIndex < _folderVideos.length - 1;
    if (hasNext) {
      final nextVideo = _folderVideos[_currentIndex + 1];
      _loadVideo(nextVideo);
    }
  }

  void _playPreviousVideo() {
    final hasPrev = _currentIndex > 0 && _currentIndex < _folderVideos.length;
    if (hasPrev) {
      final prevVideo = _folderVideos[_currentIndex - 1];
      _loadVideo(prevVideo);
    }
  }

  Future<void> _loadVideo(VideoItem newVideo) async {
    _isChangingVideo = true;
    try {
      // 1. Save current position of the active video
      await _savePosition();

      // Carry over active subtitle and audio tracks
      final subId = player.state.track.subtitle.id;
      final audioId = player.state.track.audio.id;

      // 2. Resolve parent directories to see if folder has changed
      final oldParent =
          _currentVideo != null &&
              !_currentVideo!.path.startsWith('http') &&
              !_currentVideo!.path.startsWith('asset')
          ? File(_currentVideo!.path).absolute.parent.path
          : '';
      final newParent =
          !newVideo.path.startsWith('http') &&
              !newVideo.path.startsWith('asset')
          ? File(newVideo.path).absolute.parent.path
          : '';

      _currentVideo = newVideo;
      _updateActiveVideo(newVideo);

      if (oldParent == newParent &&
          _folderVideos.isNotEmpty &&
          oldParent.isNotEmpty) {
        // Same directory, just update _currentIndex instantly!
        final idx = _folderVideos.indexWhere(
          (v) => v.path == newVideo.path || v.id == newVideo.id,
        );
        setState(() {
          _currentIndex = idx != -1 ? idx : 0;
        });
      } else {
        // Different directory, load new folder videos!
        await _loadFolderVideos(newVideo);
      }

      // 3. Reset playback states & load new video's delay offsets
      final subDelay = await MediaService().getPlayerSetting(
        '${newVideo.id}_subtitle_delay',
        'int',
      );
      final audioDelay = await MediaService().getPlayerSetting(
        '${newVideo.id}_audio_delay',
        'int',
      );

      setState(() {
        position = Duration.zero;
        duration = Duration.zero;
        isPlaying = false;
        showResumeDialog = false;
        _hasRestoredTracks = false;
        _savedSubtitleTrackId = subId;
        _savedAudioTrackId = audioId;
        _activeSubtitleDelayMs = (subDelay as int?) ?? 0;
        _activeAudioDelayMs = (audioDelay as int?) ?? 0;
        discoveredSubtitles = [];
      });

      // 4. Open the new video media in the player
      final videoPath = newVideo.path;
      await player.open(Media(videoPath), play: false);

      // 5. Apply settings
      final settings = ref.read(playerSettingsProvider);
      _applySettings(settings);

      // Try to discover sidecar subtitles
      if (!videoPath.startsWith('asset://') &&
          !videoPath.startsWith('http://') &&
          !videoPath.startsWith('https://')) {
        final sidecars = await _discoverSidecarSubtitles(videoPath);
        if (mounted) {
          setState(() {
            discoveredSubtitles = sidecars;
          });
          _restoreSavedTracks();
        }
      }

      // 7. Check autoResume setting
      if (settings.autoResume) {
        final saved = await MediaService().getPlaybackPosition(newVideo.id);
        if (saved != null) {
          final positionMs = saved['position'] as int;
          final durationMs = saved['duration'] as int;
          if (positionMs > 1000 &&
              durationMs > 0 &&
              (positionMs / durationMs) < 0.95) {
            setState(() {
              showResumeDialog = true;
              savedProgressMs = positionMs;
            });
            return; // Keep paused, wait for dialog
          }
        }
      }

      // Otherwise, play directly
      await player.play();
    } finally {
      _isChangingVideo = false;
    }
  }

  Future<List<SubtitleTrack>> _discoverSidecarSubtitles(
    String videoPath,
  ) async {
    final List<SubtitleTrack> discovered = [];
    try {
      final file = File(videoPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) return discovered;

      // Extract filename without extension
      final videoName = file.uri.pathSegments.last;
      final dotIndex = videoName.lastIndexOf('.');
      final baseName = dotIndex == -1
          ? videoName
          : videoName.substring(0, dotIndex);
      final baseNameLower = baseName.toLowerCase();

      final allowedExtensions = {'.srt', '.vtt', '.ass', '.ssa'};

      await for (final entity in parentDir.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is File) {
          final path = entity.path;
          // Get clean filename
          final name = entity.uri.pathSegments.last;
          final lastDot = name.lastIndexOf('.');
          if (lastDot == -1) continue;

          final ext = name.substring(lastDot).toLowerCase();
          if (!allowedExtensions.contains(ext)) continue;

          // Check if it starts with the video base name (case-insensitive) followed by .
          final nameLower = name.toLowerCase();
          if (nameLower.startsWith('$baseNameLower.')) {
            // Found a sidecar subtitle!
            final title = name; // Use filename as title
            discovered.add(SubtitleTrack.uri('file://$path', title: title));
          }
        }
      }
    } catch (e) {
      debugPrint('Error discovering sidecar subtitles: $e');
    }
    return discovered;
  }

  Future<void> _initSettings() async {
    final v = await MediaService().getVolume();
    final b = await MediaService().getBrightness();
    if (mounted) {
      setState(() {
        volumeValue = v;
        brightnessValue = b;
      });
    }
  }

  void _syncMediaSession() {
    final active = _activeVideo;
    if (active != null) {
      MediaService().updateActiveMediaSession(
        title: active.title,
        isPlaying: isPlaying,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
      );
    }
  }

  void _applySettings(PlayerSettingsState settings) {
    if (!speedBoostActive) {
      player.setRate(1.0);
    }
    if (settings.subtitleSettings.enabled) {
      if (activeSubtitleTrack != null) {
        player.setSubtitleTrack(activeSubtitleTrack!);
      } else {
        player.setSubtitleTrack(SubtitleTrack.auto());
      }
    } else {
      player.setSubtitleTrack(SubtitleTrack.no());
    }
    try {
      (player.platform as dynamic).setProperty(
        'sub-delay',
        '${_activeSubtitleDelayMs / 1000.0}',
      );
    } catch (_) {}
    try {
      (player.platform as dynamic).setProperty(
        'audio-delay',
        '${_activeAudioDelayMs / 1000.0}',
      );
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    final active = _activeVideo;
    if (active == null) return;
    final currentPos = position.inMilliseconds;
    final totalDur = duration.inMilliseconds;
    if (currentPos > 0 && totalDur > 0) {
      lastSavedPositionMs = currentPos;
      await MediaService().savePlaybackPosition(
        id: active.id,
        positionMs: currentPos,
        durationMs: totalDur,
        title: active.title,
        path: active.path,
      );
    }
  }

  void startHideTimer() {
    hideTimer?.cancel();
    if (isLocked) return;

    hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        showControls = false;
      });
    });
  }

  void showControlsTemporarily() {
    setState(() {
      showControls = true;
    });
    startHideTimer();
  }

  Future<void> togglePlayPause() async {
    HapticFeedback.mediumImpact();
    if (isPlaying) {
      await player.pause();
      await _savePosition();
    } else {
      await player.play();
    }
    showControlsTemporarily();
  }

  Future<void> seekBy(int seconds) async {
    final target = position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > duration
        ? duration
        : target;
    await player.seek(clamped);
    _syncMediaSession();
    showControlsTemporarily();
  }

  Future<void> enableSpeedBoost() async {
    if (isLocked || speedBoostActive) return;
    speedBoostActive = true;
    await player.setRate(2.0);
    if (mounted) setState(() {});
  }

  Future<void> disableSpeedBoost() async {
    if (isLocked || !speedBoostActive) return;
    speedBoostActive = false;
    await player.setRate(1.0);
    if (mounted) setState(() {});
  }

  // Handle Swipe Gestures for Brightness/Volume
  void _handleVerticalDragUpdate(
    DragUpdateDetails details,
    double screenWidth,
  ) {
    if (isLocked) return;

    final isLeftHalf = details.localPosition.dx < screenWidth / 2;
    // vertical delta (- means drag up, + means drag down)
    final delta = -details.primaryDelta! / 250.0;

    setState(() {
      if (isLeftHalf) {
        brightnessValue = (brightnessValue + delta).clamp(0.0, 1.0);
        showBrightnessHUD = true;
        showVolumeHUD = false;
        MediaService().setBrightness(brightnessValue);
      } else {
        volumeValue = (volumeValue + delta).clamp(0.0, 1.0);
        showVolumeHUD = true;
        showBrightnessHUD = false;
        MediaService().setVolume(volumeValue);
      }
    });

    hudOverlayTimer?.cancel();
    hudOverlayTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        showVolumeHUD = false;
        showBrightnessHUD = false;
      });
    });
  }

  // Handle Horizontal Swipe Gestures for Seeking
  void _handleHorizontalDragStart(DragStartDetails details) {
    if (isLocked) return;
    setState(() {
      isDraggingSeek = true;
      dragSecondsAccumulator = 0.0;
      targetSeekPosition = position;
      seekDeltaSeconds = 0;
    });
  }

  void _handleHorizontalDragUpdate(
    DragUpdateDetails details,
    double screenWidth,
  ) {
    if (isLocked || !isDraggingSeek) return;

    final deltaPx = details.primaryDelta ?? 0.0;
    // Map full screen width drag to 150 seconds seek range
    final secondsPerPixel = 150.0 / screenWidth;

    setState(() {
      dragSecondsAccumulator += deltaPx * secondsPerPixel;

      final targetMs =
          (position.inMilliseconds + (dragSecondsAccumulator * 1000).toInt())
              .clamp(0, duration.inMilliseconds);

      targetSeekPosition = Duration(milliseconds: targetMs);
      seekDeltaSeconds = targetSeekPosition.inSeconds - position.inSeconds;
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (isLocked || !isDraggingSeek) return;

    player.seek(targetSeekPosition).then((_) => _syncMediaSession());

    setState(() {
      isDraggingSeek = false;
      dragSecondsAccumulator = 0.0;
    });
    showControlsTemporarily();
  }

  void _setSleepTimer(String selection) {
    sleepTimer?.cancel();
    setState(() {
      activeSleepTimer = selection;
    });

    if (selection == 'Off' || selection == 'End of Video') {
      setState(() {
        sleepTimerRemaining = null;
      });
      return;
    }

    int minutes = 0;
    switch (selection) {
      case '15 Minutes':
        minutes = 15;
        break;
      case '30 Minutes':
        minutes = 30;
        break;
      case '45 Minutes':
        minutes = 45;
        break;
      case '60 Minutes':
        minutes = 60;
        break;
    }

    if (minutes > 0) {
      sleepTimerRemaining = Duration(minutes: minutes);
      sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (sleepTimerRemaining!.inSeconds <= 1) {
            sleepTimerRemaining = Duration.zero;
            timer.cancel();
            player.pause();
            sleepTimerRemaining = null;
            activeSleepTimer = 'Off';
          } else {
            sleepTimerRemaining =
                sleepTimerRemaining! - const Duration(seconds: 1);
          }
        });
      });
    }
  }

  void _showHUDNotification(String text, IconData icon) {
    setState(() {
      hudNotificationText = text;
      hudNotificationIcon = icon;
    });

    hudNotificationTimer?.cancel();
    hudNotificationTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        hudNotificationText = null;
        hudNotificationIcon = null;
      });
    });
  }

  void _toggleOrientationLock() {
    String newMode;
    IconData icon;
    if (orientationMode == 'Auto') {
      newMode = 'Portrait';
      icon = Icons.screen_lock_portrait_rounded;
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else if (orientationMode == 'Portrait') {
      newMode = 'Landscape';
      icon = Icons.screen_lock_landscape_rounded;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      newMode = 'Auto';
      icon = Icons.screen_rotation_rounded;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    setState(() {
      orientationMode = newMode;
    });

    _showHUDNotification('Orientation: $newMode', icon);
  }

  Future<void> _takeScreenshot() async {
    try {
      final bytes = await player.screenshot();
      if (bytes == null) {
        _showHUDNotification('Screenshot failed', Icons.error_outline_rounded);
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoTitle = _activeVideo?.title ?? 'video';
      final cleanTitle = videoTitle.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final fileName = 'Veil_${cleanTitle}_$timestamp';

      final result = await MediaService().saveScreenshotToGallery(
        bytes,
        fileName,
      );
      if (result != null) {
        if (mounted) {
          _showHUDNotification('Screenshot Saved', Icons.camera_alt_rounded);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0F0F0F),
              content: const Text(
                'Screenshot Saved to Pictures/Veil',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                textColor: const Color(0xFF10B981),
                label: 'Open',
                onPressed: () {
                  MediaService().openScreenshotFolder();
                },
              ),
            ),
          );
        }
      } else {
        _showHUDNotification('Screenshot failed', Icons.error_outline_rounded);
      }
    } catch (e) {
      _showHUDNotification('Screenshot failed', Icons.error_outline_rounded);
    }
  }

  Future<void> _showVideoInfo() async {
    final active = _activeVideo;
    if (active == null) return;
    final path = active.path;
    final fileName = active.title;
    final sizeBytes = active.size;

    String fileSizeStr;
    if (sizeBytes > 1024 * 1024 * 1024) {
      fileSizeStr =
          '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (sizeBytes > 1024 * 1024) {
      fileSizeStr = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      fileSizeStr = '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
    }

    final durationStr = format(duration);

    final width = player.state.width;
    final height = player.state.height;
    final aspectStr = (width != null && height != null && height > 0)
        ? (width / height).toStringAsFixed(2)
        : 'Unknown';

    final audioTracksCount = player.state.tracks.audio.length;
    final subtitleTracksCount = player.state.tracks.subtitle.length;

    // ── Media Capabilities: Run diagnostics ─────────────────────────────────
    final diagnosticsService = ref.read(mediaDiagnosticsServiceProvider);
    final diagnostics = await diagnosticsService.analyze(
      player: player,
      filePath: path,
      fileSizeBytes: sizeBytes > 0 ? sizeBytes : null,
      duration: duration,
      embeddedSubtitleCount: subtitleTracksCount,
      externalSubtitleCount: discoveredSubtitles.length,
    );

    // Cache diagnostics globally
    if (mounted) {
      ref.read(currentDiagnosticsProvider.notifier).state = diagnostics;
      CrashHandler.currentDecoder = diagnostics.hwDecodeDisplayName;
    }

    if (!mounted) return;

    PlayerMenuSheets.showVideoInfo(
      context: context,
      fileName: fileName,
      path: path,
      fileSize: fileSizeStr,
      duration: durationStr,
      aspectRatio: aspectStr,
      audioTracksCount: audioTracksCount,
      subtitleTracksCount: subtitleTracksCount,
      diagnostics: diagnostics,
    );
  }

  String format(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
    return "${twoDigits(minutes)}:${twoDigits(seconds)}";
  }

  String formatSleepTimer(Duration? d) {
    if (d == null) return '';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return "$minutes:${twoDigits(seconds)}";
  }

  Future<void> _pickExternalSubtitle() async {
    try {
      final path = await ref.read(mediaRepositoryProvider).pickSubtitleFile();
      if (path != null) {
        final fileUri = 'file://$path';
        final fileName = path.split('/').last;

        final externalTrack = SubtitleTrack.uri(fileUri, title: fileName);
        await player.setSubtitleTrack(externalTrack);

        setState(() {
          activeSubtitleTrack = externalTrack;
        });

        final active = _activeVideo;
        if (active != null) {
          await MediaService().savePlayerSetting(
            '${active.id}_subtitle_track_id',
            externalTrack.id,
          );
        }

        _showHUDNotification(
          'Loaded Subtitle: $fileName',
          Icons.subtitles_rounded,
        );
      }
    } catch (e) {
      _showHUDNotification(
        'Failed to load subtitle',
        Icons.error_outline_rounded,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_isInPipMode) {
        player.pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.video != null || _currentVideo != null) {
      MediaService().setPipEnabled(false);
    }
    _savePosition();
    hideTimer?.cancel();
    hudOverlayTimer?.cancel();
    hudNotificationTimer?.cancel();
    sleepTimer?.cancel();

    positionSub?.cancel();
    durationSub?.cancel();
    playingSub?.cancel();
    completedSub?.cancel();
    tracksSub?.cancel();
    errorSub?.cancel();

    // Clear session-scoped media capabilities state
    try {
      ref.read(currentDiagnosticsProvider.notifier).state = null;
      ref.read(currentPlaybackErrorProvider.notifier).state = null;
    } catch (_) {}

    MethodChannelDispatcher.removeListener(_handleMethodCall);
    _updateActiveVideo(null);

    player.dispose();

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipModeChanged':
        final isInPip = call.arguments as bool;
        if (mounted) {
          setState(() {
            _isInPipMode = isInPip;
          });
        }
        break;
      case 'onMediaButtonPlay':
        player.play();
        break;
      case 'onMediaButtonPause':
        player.pause();
        break;
      case 'onMediaButtonToggle':
        if (player.state.playing) {
          player.pause();
        } else {
          player.play();
        }
        break;
      case 'onMediaButtonNext':
        _playNextVideo();
        break;
      case 'onMediaButtonPrevious':
        _playPreviousVideo();
        break;
      case 'onMediaButtonSeekTo':
        final pos = call.arguments as int;
        player.seek(Duration(milliseconds: pos));
        break;
      case 'onAudioFocusLoss':
        final isTransient = call.arguments as bool;
        if (isTransient) {
          if (player.state.playing) {
            _pausedForAudioFocus = true;
            player.pause();
          }
        } else {
          _pausedForAudioFocus = false;
          player.pause();
        }
        break;
      case 'onAudioFocusGain':
        if (_pausedForAudioFocus) {
          _pausedForAudioFocus = false;
          player.play();
        }
        break;
      case 'onAudioFocusDuck':
        if (player.state.playing) {
          _pausedForAudioFocus = true;
          player.pause();
        }
        break;
    }
  }

  void _updateActiveVideo(VideoItem? video) {
    if (video == null) {
      try {
        ref.read(activeVideoProvider.notifier).state = null;
      } catch (_) {}
    } else {
      Future.microtask(() {
        if (mounted) {
          ref.read(activeVideoProvider.notifier).state = video;
        }
      });
    }
    CrashHandler.currentScreen = video != null ? 'PlayerScreen' : null;
    CrashHandler.currentMediaFile = video?.path;
    final settings = ref.read(playerSettingsProvider);
    CrashHandler.currentDecoder = video != null
        ? (settings.hwDecoding ? 'Hardware (Preferred)' : 'Software')
        : null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VideoItem?>(activeVideoProvider, (previous, next) {
      if (next == null && mounted && previous != null) {
        Navigator.of(context).pop();
      }
    });
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final maxDuration = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();

    final settings = ref.watch(playerSettingsProvider);
    final ratioMode = settings.preferredAspectRatio;

    BoxFit videoFit = BoxFit.contain;
    bool useCustomAspectRatio = false;
    double customRatio = 1.0;

    switch (ratioMode) {
      case 'Fit':
        videoFit = BoxFit.contain;
        break;
      case 'Fill':
        videoFit = BoxFit.cover;
        break;
      case 'Stretch':
        videoFit = BoxFit.fill;
        break;
      case '16:9':
        useCustomAspectRatio = true;
        customRatio = 16 / 9;
        videoFit = BoxFit.fill;
        break;
      case '4:3':
        useCustomAspectRatio = true;
        customRatio = 4 / 3;
        videoFit = BoxFit.fill;
        break;
      case 'Original':
        if (player.state.width != null &&
            player.state.height != null &&
            player.state.height! > 0) {
          useCustomAspectRatio = true;
          customRatio = player.state.width! / player.state.height!;
          videoFit = BoxFit.fill;
        } else {
          videoFit = BoxFit.contain;
        }
        break;
    }

    final subSettings = settings.subtitleSettings;
    final baseTextColor = Color(
      int.parse(subSettings.textColor.replaceFirst('#', '0xFF')),
    );
    final finalTextColor = baseTextColor.withValues(alpha: subSettings.opacity);

    Color finalBgColor;
    if (subSettings.backgroundColor == '#00000000') {
      finalBgColor = Colors.transparent;
    } else if (subSettings.backgroundColor == '#80000000') {
      finalBgColor = Colors.black.withValues(alpha: 0.5 * subSettings.opacity);
    } else {
      finalBgColor = Colors.black.withValues(alpha: 1.0 * subSettings.opacity);
    }

    Widget videoWidget = Video(
      controller: controller,
      controls: NoVideoControls,
      fit: videoFit,
      subtitleViewConfiguration: SubtitleViewConfiguration(
        visible: subSettings.enabled,
        style: TextStyle(
          fontSize: subSettings.fontSize,
          color: finalTextColor,
          backgroundColor: finalBgColor,
        ),
        padding: EdgeInsets.only(
          bottom: size.height * subSettings.verticalPosition,
          left: 24,
          right: 24,
        ),
      ),
    );

    if (useCustomAspectRatio) {
      videoWidget = Center(
        child: AspectRatio(aspectRatio: customRatio, child: videoWidget),
      );
    }

    // Keep settings synchronized on provider updates
    ref.listen<PlayerSettingsState>(playerSettingsProvider, (prev, next) {
      _applySettings(next);
    });

    if (_isInPipMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: RepaintBoundary(child: videoWidget)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Video Player surface
          Positioned.fill(child: RepaintBoundary(child: videoWidget)),

          // 2. Gesture Detector Layer
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (isLocked) {
                  showControlsTemporarily();
                } else {
                  if (showControls) {
                    setState(() {
                      showControls = false;
                    });
                  } else {
                    showControlsTemporarily();
                  }
                }
              },
              onVerticalDragUpdate: (details) =>
                  _handleVerticalDragUpdate(details, size.width),
              onHorizontalDragStart: _handleHorizontalDragStart,
              onHorizontalDragUpdate: (details) =>
                  _handleHorizontalDragUpdate(details, size.width),
              onHorizontalDragEnd: _handleHorizontalDragEnd,
              child: Row(
                children: [
                  // Left Screen Half Gestures
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: isLocked
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                showDoubleTapRippleLeft = true;
                              });
                              seekBy(-10);
                            },
                    ),
                  ),
                  // Right Screen Half Gestures
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: isLocked
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                showDoubleTapRippleRight = true;
                              });
                              seekBy(10);
                            },
                      onLongPressStart: isLocked
                          ? null
                          : (_) => enableSpeedBoost(),
                      onLongPressEnd: isLocked
                          ? null
                          : (_) => disableSpeedBoost(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Double Tap Ripples
          if (showDoubleTapRippleLeft)
            DoubleTapRipple(
              isLeft: true,
              onCompleted: () =>
                  setState(() => showDoubleTapRippleLeft = false),
            ),
          if (showDoubleTapRippleRight)
            DoubleTapRipple(
              isLeft: false,
              onCompleted: () =>
                  setState(() => showDoubleTapRippleRight = false),
            ),

          // 4. Horizontal Seek Gesture HUD
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isDraggingSeek ? 1.0 : 0.0,
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !isDraggingSeek,
                child: SeekGestureOverlay(
                  targetPosition: targetSeekPosition,
                  totalDuration: duration,
                  deltaSeconds: seekDeltaSeconds,
                ),
              ),
            ),
          ),

          // 5. Locked State Floating Button
          if (isLocked && showControls)
            Positioned(
              left: 24,
              top: 24,
              child: SafeArea(
                child: VeilButton(
                  type: VeilButtonType.primary,
                  icon: Icons.lock_open_rounded,
                  label: 'Unlock UI',
                  onTap: () {
                    setState(() {
                      isLocked = false;
                    });
                    showControlsTemporarily();
                  },
                ),
              ),
            ),

          // 6. Swipe HUD / Indicators
          if (showVolumeHUD)
            Positioned(
              right: 24,
              top: size.height / 2 - 90,
              child: BrightnessVolumeOverlay(
                isVolume: true,
                value: volumeValue,
              ),
            ),
          if (showBrightnessHUD)
            Positioned(
              left: 24,
              top: size.height / 2 - 90,
              child: BrightnessVolumeOverlay(
                isVolume: false,
                value: brightnessValue,
              ),
            ),

          if (speedBoostActive) const Center(child: SpeedOverlay()),

          // 7. General HUD notifications (Aspect ratio / Orientation changes)
          if (hudNotificationText != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E1E1E), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hudNotificationIcon,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hudNotificationText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 8. Playback Error HUD (Media Capabilities Layer)
          if (_showPlaybackError && _currentPlaybackError != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _showPlaybackError = false),
                child: AnimatedOpacity(
                  opacity: _showPlaybackError ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0A0A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentPlaybackError!.title,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentPlaybackError!.description,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentPlaybackError!.suggestion,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showPlaybackError = false),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 9. Playback Controls Overlay (Top bar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: (showControls && !isLocked) ? 1.0 : 0.0,
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !(showControls && !isLocked),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          VeilButton(
                            type: VeilButtonType.icon,
                            icon: Icons.arrow_back_ios_new_rounded,
                            iconColor: Colors.white,
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (sleepTimerRemaining != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8.0,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: theme.colorScheme.primary,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.timer_rounded,
                                              color: theme.colorScheme.primary,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              formatSleepTimer(
                                                sleepTimerRemaining,
                                              ),
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.primary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.subtitles_rounded,
                                    iconColor: Colors.white,
                                    onTap: () {
                                      final uniqueTracks =
                                          <String, SubtitleTrack>{};
                                      for (final track in subtitleTracks) {
                                        uniqueTracks[track.id] = track;
                                      }
                                      for (final track in discoveredSubtitles) {
                                        uniqueTracks[track.id] = track;
                                      }

                                      PlayerMenuSheets.showSubtitleSettings(
                                        context: context,
                                        settings: settings.subtitleSettings,
                                        tracks: uniqueTracks.values.toList(),
                                        activeTrack:
                                            player.state.track.subtitle,
                                        currentDelayMs: _activeSubtitleDelayMs,
                                        onChanged: (newSettings) {
                                          ref
                                              .read(
                                                playerSettingsProvider.notifier,
                                              )
                                              .updateSubtitleSettings(
                                                newSettings,
                                              );
                                        },
                                        onTrackSelected: (track) {
                                          player.setSubtitleTrack(track);
                                          setState(() {
                                            activeSubtitleTrack = track;
                                          });
                                          final activeVid = _activeVideo;
                                          if (activeVid != null) {
                                            MediaService().savePlayerSetting(
                                              '${activeVid.id}_subtitle_track_id',
                                              track.id,
                                            );
                                          }
                                        },
                                        onDelayChanged: (delay) {
                                          setState(() {
                                            _activeSubtitleDelayMs = delay;
                                          });
                                          try {
                                            (player.platform as dynamic)
                                                .setProperty(
                                                  'sub-delay',
                                                  '${delay / 1000.0}',
                                                );
                                          } catch (_) {}
                                          final activeVid = _activeVideo;
                                          if (activeVid != null) {
                                            MediaService().savePlayerSetting(
                                              '${activeVid.id}_subtitle_delay',
                                              delay,
                                            );
                                          }
                                        },
                                        onAddExternal: _pickExternalSubtitle,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.audiotrack_rounded,
                                    iconColor: Colors.white,
                                    onTap: () {
                                      final tracks = player.state.tracks.audio;
                                      final selectedTrack =
                                          player.state.track.audio;
                                      PlayerMenuSheets.showAudioTrackSettings(
                                        context: context,
                                        tracks: tracks,
                                        selectedTrack: selectedTrack,
                                        currentDelayMs: _activeAudioDelayMs,
                                        onSelected: (track) {
                                          player.setAudioTrack(track);
                                          final activeVid = _activeVideo;
                                          if (activeVid != null) {
                                            MediaService().savePlayerSetting(
                                              '${activeVid.id}_audio_track_id',
                                              track.id,
                                            );
                                          }
                                        },
                                        onDelayChanged: (delay) {
                                          setState(() {
                                            _activeAudioDelayMs = delay;
                                          });
                                          try {
                                            (player.platform as dynamic)
                                                .setProperty(
                                                  'audio-delay',
                                                  '${delay / 1000.0}',
                                                );
                                          } catch (_) {}
                                          final activeVid = _activeVideo;
                                          if (activeVid != null) {
                                            MediaService().savePlayerSetting(
                                              '${activeVid.id}_audio_delay',
                                              delay,
                                            );
                                          }
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.timer_rounded,
                                    iconColor: Colors.white,
                                    onTap: () =>
                                        PlayerMenuSheets.showSleepTimerSettings(
                                          context: context,
                                          activeTimer: activeSleepTimer,
                                          onSelected: (val) {
                                            _setSleepTimer(val);
                                          },
                                        ),
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.aspect_ratio_rounded,
                                    iconColor: Colors.white,
                                    onTap: () {
                                      PlayerMenuSheets.showAspectRatioSettings(
                                        context: context,
                                        currentRatio:
                                            settings.preferredAspectRatio,
                                        onSelected: (val) {
                                          ref
                                              .read(
                                                playerSettingsProvider.notifier,
                                              )
                                              .setPreferredAspectRatio(val);

                                          IconData displayIcon =
                                              Icons.aspect_ratio_rounded;
                                          if (val == 'Fill') {
                                            displayIcon =
                                                Icons.fullscreen_rounded;
                                          }
                                          if (val == 'Stretch') {
                                            displayIcon =
                                                Icons.fit_screen_rounded;
                                          }

                                          _showHUDNotification(
                                            'Aspect Ratio: $val',
                                            displayIcon,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: orientationMode == 'Auto'
                                        ? Icons.screen_rotation_rounded
                                        : orientationMode == 'Portrait'
                                        ? Icons.screen_lock_portrait_rounded
                                        : Icons.screen_lock_landscape_rounded,
                                    iconColor: Colors.white,
                                    onTap: _toggleOrientationLock,
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.camera_alt_rounded,
                                    iconColor: Colors.white,
                                    onTap: _takeScreenshot,
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.picture_in_picture_alt_rounded,
                                    iconColor: Colors.white,
                                    onTap: () {
                                      MediaService().enterPip();
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.info_outline_rounded,
                                    iconColor: Colors.white,
                                    onTap: _showVideoInfo,
                                  ),
                                  const SizedBox(width: 8),
                                  VeilButton(
                                    type: VeilButtonType.icon,
                                    icon: Icons.lock_outline_rounded,
                                    iconColor: Colors.white,
                                    onTap: () {
                                      setState(() {
                                        isLocked = true;
                                        showControls = false;
                                      });
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
                ),
              ),
            ),
          ),

          // 8b. Playback Controls Overlay (Bottom bar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: (showControls && !isLocked) ? 1.0 : 0.0,
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !(showControls && !isLocked),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VeilSlider(
                            value: isDraggingScrubber
                                ? scrubberDragValue
                                : position.inMilliseconds
                                      .clamp(0, maxDuration.toInt())
                                      .toDouble(),
                            min: 0,
                            max: maxDuration,
                            onChangeStart: (val) {
                              setState(() {
                                isDraggingScrubber = true;
                                scrubberDragValue = val;
                              });
                              showControlsTemporarily();
                            },
                            onChanged: (val) {
                              setState(() {
                                scrubberDragValue = val;
                              });
                              showControlsTemporarily();
                            },
                            onChangeEnd: (val) {
                              player
                                  .seek(Duration(milliseconds: val.toInt()))
                                  .then((_) {
                                    if (mounted) {
                                      setState(() {
                                        isDraggingScrubber = false;
                                      });
                                      _syncMediaSession();
                                    }
                                  });
                              showControlsTemporarily();
                            },
                          ),
                          const SizedBox(height: 8),
                          // Details & Playback button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                format(
                                  isDraggingScrubber
                                      ? Duration(
                                          milliseconds: scrubberDragValue
                                              .toInt(),
                                        )
                                      : position,
                                ),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              Text(
                                format(duration),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Centered playback buttons row
                          Row(
                            children: [
                              // 1. Far Left: Spacer/Empty box
                              const Expanded(child: SizedBox.shrink()),
                              // 2. Center: Skip Previous, Play/Pause, Skip Next
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSkipPreviousButton(theme),
                                  const SizedBox(width: 24),
                                  Tooltip(
                                    message: isPlaying ? 'Pause' : 'Play',
                                    child: VeilButton(
                                      type: VeilButtonType.primary,
                                      shape: BoxShape.circle,
                                      width: 56,
                                      height: 56,
                                      icon: isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      iconSize: 34,
                                      onTap: togglePlayPause,
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  _buildSkipNextButton(theme),
                                ],
                              ),
                              // 3. Far Right: Folder Videos Button
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Tooltip(
                                    message: 'Folder Videos',
                                    child: VeilButton(
                                      type: VeilButtonType.icon,
                                      icon: Icons.queue_music_rounded,
                                      iconColor: showQueuePanel
                                          ? theme.colorScheme.primary
                                          : Colors.white38,
                                      iconSize: 22,
                                      height: 48,
                                      width: 48,
                                      onTap: () {
                                        setState(() {
                                          showQueuePanel = !showQueuePanel;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 9. AMOLED Resume Playback Dialog
          if (showResumeDialog)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Container(
                    width: 300,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Resume Playback?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Do you want to resume from ${format(Duration(milliseconds: savedProgressMs))}?',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    showResumeDialog = false;
                                  });
                                  player.seek(Duration.zero).then((_) {
                                    _syncMediaSession();
                                    player.play();
                                  });
                                },
                                child: const Text(
                                  'Start Over',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    showResumeDialog = false;
                                  });
                                  player
                                      .seek(
                                        Duration(milliseconds: savedProgressMs),
                                      )
                                      .then((_) {
                                        _syncMediaSession();
                                        player.play();
                                      });
                                },
                                child: const Text(
                                  'Resume',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 10. Queue Panel click-outside catcher
          if (showQueuePanel)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    showQueuePanel = false;
                  });
                },
                child: const SizedBox.expand(),
              ),
            ),

          // 11. Queue Panel sliding overlay
          _buildQueuePanel(size, theme),
        ],
      ),
    );
  }

  Widget _buildSkipPreviousButton(ThemeData theme) {
    final hasPrev = _currentIndex > 0;
    return Tooltip(
      message: 'Previous Video',
      child: VeilButton(
        type: VeilButtonType.icon,
        icon: Icons.skip_previous_rounded,
        iconColor: hasPrev ? Colors.white : Colors.white24,
        iconSize: 28,
        height: 48,
        width: 48,
        isDisabled: !hasPrev,
        onTap: hasPrev ? _playPreviousVideo : null,
      ),
    );
  }

  Widget _buildSkipNextButton(ThemeData theme) {
    final hasNext =
        _currentIndex >= 0 && _currentIndex < _folderVideos.length - 1;
    return Tooltip(
      message: 'Next Video',
      child: VeilButton(
        type: VeilButtonType.icon,
        icon: Icons.skip_next_rounded,
        iconColor: hasNext ? Colors.white : Colors.white24,
        iconSize: 28,
        height: 48,
        width: 48,
        isDisabled: !hasNext,
        onTap: hasNext ? _playNextVideo : null,
      ),
    );
  }

  Widget _buildQueuePanel(Size size, ThemeData theme) {
    final double panelWidth = size.width * 0.45;
    final double width = panelWidth.clamp(280.0, 420.0);

    return AnimatedPositioned(
      duration: VeilMotion.emphasized,
      curve: VeilMotion.curve,
      top: 0,
      bottom: 0,
      right: showQueuePanel ? 0 : -width - 20,
      child: GestureDetector(
        onTap: () {}, // swallow clicks inside the panel
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.95),
            border: const Border(
              left: BorderSide(color: Color(0xFF1E1E1E), width: 1.2),
            ),
          ),
          child: FolderQueuePanel(
            currentVideo: _currentVideo,
            videos: _folderVideos,
            isLoading: _isLoadingFolderVideos,
            onVideoSelected: (newVideo) {
              _loadVideo(newVideo);
            },
            onClose: () {
              setState(() {
                showQueuePanel = false;
              });
            },
          ),
        ),
      ),
    );
  }
}
