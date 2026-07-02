import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectionModeProvider = StateProvider<bool>((ref) => false);

final selectedVideosProvider =
    StateNotifierProvider<SelectedVideosNotifier, Set<String>>((ref) {
      return SelectedVideosNotifier(ref);
    });

class SelectedVideosNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;

  SelectedVideosNotifier(this._ref) : super({});

  void toggle(String videoId) {
    HapticFeedback.selectionClick();
    if (state.contains(videoId)) {
      state = {...state}..remove(videoId);
      if (state.isEmpty) {
        _ref.read(selectionModeProvider.notifier).state = false;
      }
    } else {
      if (state.isEmpty) {
        _ref.read(selectionModeProvider.notifier).state = true;
      }
      state = {...state, videoId};
    }
  }

  void selectAll(List<String> videoIds) {
    state = {...videoIds};
  }

  void clear() {
    state = {};
    _ref.read(selectionModeProvider.notifier).state = false;
  }
}
