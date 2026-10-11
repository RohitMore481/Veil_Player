import 'audio_queue_state.dart';

class AudioSettings {
  final AudioRepeatMode defaultRepeatMode;
  final bool defaultShuffle;
  final bool pauseOnHeadsetDisconnect;

  const AudioSettings({
    this.defaultRepeatMode = AudioRepeatMode.off,
    this.defaultShuffle = false,
    this.pauseOnHeadsetDisconnect = true,
  });

  AudioSettings copyWith({
    AudioRepeatMode? defaultRepeatMode,
    bool? defaultShuffle,
    bool? pauseOnHeadsetDisconnect,
  }) {
    return AudioSettings(
      defaultRepeatMode: defaultRepeatMode ?? this.defaultRepeatMode,
      defaultShuffle: defaultShuffle ?? this.defaultShuffle,
      pauseOnHeadsetDisconnect:
          pauseOnHeadsetDisconnect ?? this.pauseOnHeadsetDisconnect,
    );
  }

  Map<String, dynamic> toMap() => {
        'defaultRepeatMode': defaultRepeatMode.name,
        'defaultShuffle': defaultShuffle,
        'pauseOnHeadsetDisconnect': pauseOnHeadsetDisconnect,
      };

  factory AudioSettings.fromMap(Map<dynamic, dynamic> map) {
    final repeatName = map['defaultRepeatMode'] as String? ?? 'off';
    final repeatMode = AudioRepeatMode.values.firstWhere(
      (m) => m.name == repeatName,
      orElse: () => AudioRepeatMode.off,
    );

    return AudioSettings(
      defaultRepeatMode: repeatMode,
      defaultShuffle: map['defaultShuffle'] as bool? ?? false,
      pauseOnHeadsetDisconnect:
          map['pauseOnHeadsetDisconnect'] as bool? ?? true,
    );
  }
}
