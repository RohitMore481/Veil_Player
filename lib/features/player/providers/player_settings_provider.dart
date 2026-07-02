import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../library/repositories/media_repository.dart';
import '../../library/providers/media_provider.dart';
import '../models/subtitle_settings.dart';

class PlayerSettingsState {
  final String preferredAspectRatio;
  final SubtitleSettings subtitleSettings;
  final bool autoResume;
  final bool autoPlayNext;
  final String repeatMode;
  final bool hwDecoding;
  final bool batterySaverMode;
  final int thumbnailCacheSize;
  final bool amoledPureBlack;
  final String themeAccent;
  final String themeMode;

  PlayerSettingsState({
    required this.preferredAspectRatio,
    required this.subtitleSettings,
    required this.autoResume,
    required this.autoPlayNext,
    required this.repeatMode,
    required this.hwDecoding,
    required this.batterySaverMode,
    required this.thumbnailCacheSize,
    required this.amoledPureBlack,
    required this.themeAccent,
    required this.themeMode,
  });

  PlayerSettingsState copyWith({
    String? preferredAspectRatio,
    SubtitleSettings? subtitleSettings,
    bool? autoResume,
    bool? autoPlayNext,
    String? repeatMode,
    bool? hwDecoding,
    bool? batterySaverMode,
    int? thumbnailCacheSize,
    bool? amoledPureBlack,
    String? themeAccent,
    String? themeMode,
  }) {
    return PlayerSettingsState(
      preferredAspectRatio: preferredAspectRatio ?? this.preferredAspectRatio,
      subtitleSettings: subtitleSettings ?? this.subtitleSettings,
      autoResume: autoResume ?? this.autoResume,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      repeatMode: repeatMode ?? this.repeatMode,
      hwDecoding: hwDecoding ?? this.hwDecoding,
      batterySaverMode: batterySaverMode ?? this.batterySaverMode,
      thumbnailCacheSize: thumbnailCacheSize ?? this.thumbnailCacheSize,
      amoledPureBlack: amoledPureBlack ?? this.amoledPureBlack,
      themeAccent: themeAccent ?? this.themeAccent,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class PlayerSettingsNotifier extends StateNotifier<PlayerSettingsState> {
  final MediaRepository _repository;

  PlayerSettingsNotifier(this._repository)
    : super(
        PlayerSettingsState(
          preferredAspectRatio: 'Fit',
          subtitleSettings: const SubtitleSettings(),
          autoResume: true,
          autoPlayNext: false,
          repeatMode: 'off',
          hwDecoding: true,
          batterySaverMode: false,
          thumbnailCacheSize: 200,
          amoledPureBlack: true,
          themeAccent: 'Emerald',
          themeMode: 'Dark',
        ),
      ) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      final allSettings = await _repository.getAllPlayerSettings();

      final aspect = allSettings['preferred_aspect_ratio'];
      final subEnabled = allSettings['subtitle_enabled'];
      final subSize = allSettings['subtitle_font_size'];
      final subColor = allSettings['subtitle_text_color'];
      final subBg = allSettings['subtitle_bg_color'];
      final subPos = allSettings['subtitle_vertical_position'];
      final subOpacity = allSettings['subtitle_opacity'];

      final autoRes = allSettings['auto_resume'];
      final autoPlay = allSettings['auto_play_next'];
      final repMode = allSettings['repeat_mode'];
      final hwDec = allSettings['hw_decoding'];
      final battSaver = allSettings['battery_saver_mode'];
      final cacheSize = allSettings['thumbnail_cache_size'];
      final amoled = allSettings['amoled_pure_black'];
      final accent = allSettings['theme_accent'];
      final tMode = allSettings['theme_mode'];

      state = PlayerSettingsState(
        preferredAspectRatio: (aspect as String?) ?? 'Fit',
        subtitleSettings: SubtitleSettings(
          enabled: (subEnabled as bool?) ?? true,
          fontSize: (subSize as num?)?.toDouble() ?? 18.0,
          textColor: (subColor as String?) ?? '#FFFFFF',
          backgroundColor: (subBg as String?) ?? '#00000000',
          verticalPosition: (subPos as num?)?.toDouble() ?? 0.08,
          opacity: (subOpacity as num?)?.toDouble() ?? 1.0,
        ),
        autoResume: (autoRes as bool?) ?? true,
        autoPlayNext: (autoPlay as bool?) ?? false,
        repeatMode: (repMode as String?) ?? 'off',
        hwDecoding: (hwDec as bool?) ?? true,
        batterySaverMode: (battSaver as bool?) ?? false,
        thumbnailCacheSize: (cacheSize as int?) ?? 200,
        amoledPureBlack: (amoled as bool?) ?? true,
        themeAccent: (accent as String?) ?? 'Emerald',
        themeMode: (tMode as String?) ?? 'Dark',
      );
    } catch (_) {}
  }

  Future<void> setPreferredAspectRatio(String aspect) async {
    state = state.copyWith(preferredAspectRatio: aspect);
    await _repository.savePlayerSetting('preferred_aspect_ratio', aspect);
  }

  Future<void> updateSubtitleSettings(SubtitleSettings subtitleSettings) async {
    state = state.copyWith(subtitleSettings: subtitleSettings);
    await _repository.savePlayerSetting(
      'subtitle_enabled',
      subtitleSettings.enabled,
    );
    await _repository.savePlayerSetting(
      'subtitle_font_size',
      subtitleSettings.fontSize,
    );
    await _repository.savePlayerSetting(
      'subtitle_text_color',
      subtitleSettings.textColor,
    );
    await _repository.savePlayerSetting(
      'subtitle_bg_color',
      subtitleSettings.backgroundColor,
    );
    await _repository.savePlayerSetting(
      'subtitle_vertical_position',
      subtitleSettings.verticalPosition,
    );
    await _repository.savePlayerSetting(
      'subtitle_opacity',
      subtitleSettings.opacity,
    );
  }

  Future<void> setAutoResume(bool val) async {
    state = state.copyWith(autoResume: val);
    await _repository.savePlayerSetting('auto_resume', val);
  }

  Future<void> setAutoPlayNext(bool val) async {
    state = state.copyWith(autoPlayNext: val);
    await _repository.savePlayerSetting('auto_play_next', val);
  }

  Future<void> setRepeatMode(String val) async {
    state = state.copyWith(repeatMode: val);
    await _repository.savePlayerSetting('repeat_mode', val);
  }

  Future<void> setHwDecoding(bool val) async {
    state = state.copyWith(hwDecoding: val);
    await _repository.savePlayerSetting('hw_decoding', val);
  }

  Future<void> setBatterySaverMode(bool val) async {
    state = state.copyWith(batterySaverMode: val);
    await _repository.savePlayerSetting('battery_saver_mode', val);
  }

  Future<void> setThumbnailCacheSize(int val) async {
    state = state.copyWith(thumbnailCacheSize: val);
    await _repository.savePlayerSetting('thumbnail_cache_size', val);
  }

  Future<void> setAmoledPureBlack(bool val) async {
    state = state.copyWith(amoledPureBlack: val);
    await _repository.savePlayerSetting('amoled_pure_black', val);
  }

  Future<void> setThemeAccent(String val) async {
    state = state.copyWith(themeAccent: val);
    await _repository.savePlayerSetting('theme_accent', val);
  }

  Future<void> setThemeMode(String val) async {
    state = state.copyWith(themeMode: val);
    await _repository.savePlayerSetting('theme_mode', val);
  }
}

final playerSettingsProvider =
    StateNotifierProvider<PlayerSettingsNotifier, PlayerSettingsState>((ref) {
      return PlayerSettingsNotifier(ref.watch(mediaRepositoryProvider));
    });
