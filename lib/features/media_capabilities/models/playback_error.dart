/// Classification of a playback failure.
enum PlaybackErrorKind {
  /// The video codec in the file is not supported.
  unsupportedVideoCodec,

  /// The audio codec in the file is not supported.
  unsupportedAudioCodec,

  /// The container/muxer format is not supported.
  unsupportedContainer,

  /// The file appears to be corrupted or truncated.
  corruptedFile,

  /// A required track (video or audio) is missing from the container.
  missingTrack,

  /// The container reported an error during demuxing.
  containerError,

  /// A network resource could not be reached.
  networkError,

  /// The error could not be specifically classified.
  unknown,
}

/// A structured representation of a playback failure.
///
/// Used to surface clear, non-silent diagnostics to the user instead of
/// letting errors fail quietly.
class PlaybackError {
  /// The classified type of this failure.
  final PlaybackErrorKind kind;

  /// The raw error message from the media runtime (e.g. mpv error string).
  final String? rawMessage;

  /// The codec or container id involved in the failure, if known.
  final String? codecOrContainer;

  /// When the error was detected.
  final DateTime detectedAt;

  const PlaybackError({
    required this.kind,
    required this.detectedAt,
    this.rawMessage,
    this.codecOrContainer,
  });

  /// Short user-facing title for display in the HUD or error sheet.
  String get title {
    switch (kind) {
      case PlaybackErrorKind.unsupportedVideoCodec:
        return 'Unsupported Video Codec';
      case PlaybackErrorKind.unsupportedAudioCodec:
        return 'Unsupported Audio Codec';
      case PlaybackErrorKind.unsupportedContainer:
        return 'Unsupported Container';
      case PlaybackErrorKind.corruptedFile:
        return 'Corrupted File';
      case PlaybackErrorKind.missingTrack:
        return 'Missing Track';
      case PlaybackErrorKind.containerError:
        return 'Container Error';
      case PlaybackErrorKind.networkError:
        return 'Network Error';
      case PlaybackErrorKind.unknown:
        return 'Playback Error';
    }
  }

  /// Contextual explanation shown below the title.
  String get description {
    switch (kind) {
      case PlaybackErrorKind.unsupportedVideoCodec:
        final codec = codecOrContainer;
        return codec != null
            ? 'The video codec "$codec" is not supported by this version of Veil.'
            : 'The video track uses a codec that Veil cannot decode.';
      case PlaybackErrorKind.unsupportedAudioCodec:
        final codec = codecOrContainer;
        return codec != null
            ? 'The audio codec "$codec" is not supported by this version of Veil.'
            : 'The audio track uses a codec that Veil cannot decode.';
      case PlaybackErrorKind.unsupportedContainer:
        final container = codecOrContainer;
        return container != null
            ? 'The container format "$container" is not supported.'
            : 'The file container format is not supported.';
      case PlaybackErrorKind.corruptedFile:
        return 'The file appears to be corrupted or incomplete. Try re-downloading or repairing it.';
      case PlaybackErrorKind.missingTrack:
        return 'A required media track is missing from the file.';
      case PlaybackErrorKind.containerError:
        return 'An error occurred while reading the file container. The file may be damaged.';
      case PlaybackErrorKind.networkError:
        return 'Could not reach the network resource. Check your connection and try again.';
      case PlaybackErrorKind.unknown:
        return rawMessage != null
            ? 'Playback failed: $rawMessage'
            : 'An unknown playback error occurred.';
    }
  }

  /// Suggestion for what the user can do.
  String get suggestion {
    switch (kind) {
      case PlaybackErrorKind.unsupportedVideoCodec:
      case PlaybackErrorKind.unsupportedAudioCodec:
      case PlaybackErrorKind.unsupportedContainer:
        return 'A future codec pack may add support for this format.';
      case PlaybackErrorKind.corruptedFile:
        return 'Try obtaining a fresh copy of the file.';
      case PlaybackErrorKind.missingTrack:
        return 'Check if the file has a valid video or audio stream.';
      case PlaybackErrorKind.containerError:
        return 'Try re-downloading the file or converting it to MKV/MP4.';
      case PlaybackErrorKind.networkError:
        return 'Check your network connection and try again.';
      case PlaybackErrorKind.unknown:
        return 'Try a different file or check the file integrity.';
    }
  }

  @override
  String toString() => 'PlaybackError($kind: ${rawMessage ?? description})';
}
