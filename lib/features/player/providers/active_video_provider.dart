import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../library/models/video_item.dart';

/// Exposes the video item that is currently loaded in the active PlayerScreen.
///
/// If null, no active media is currently playing.
final activeVideoProvider = StateProvider<VideoItem?>((ref) => null);
