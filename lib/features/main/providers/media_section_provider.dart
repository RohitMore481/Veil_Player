import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MediaSection {
  video,
  music,
}

final mediaSectionProvider = StateProvider<MediaSection>((ref) => MediaSection.video);
