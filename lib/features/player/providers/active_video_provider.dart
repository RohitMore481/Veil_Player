import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../library/models/video_item.dart';

/// Exposes the video item that is currently loaded in the active PlayerScreen.
///
/// If null, no active media is currently playing.
final activeVideoProvider = StateProvider<VideoItem?>((ref) => null);

/// Tracks the unique session identifier of the active PlayerScreen to prevent
/// cleanup operations from previous sessions from stomping on a newly opened session.
final activeVideoSessionIdProvider = StateProvider<String?>((ref) => null);
