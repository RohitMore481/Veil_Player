/// Privacy Sanitizer for Veil Player Diagnostics.
///
/// HARD REQUIREMENT:
/// Prevents user-identifiable data, private filenames, personal directory paths,
/// media content, and environment metadata from leaking into diagnostic reports.
class DiagnosticSanitizer {
  // Regex for Android external storage paths (e.g. /storage/emulated/0/Movies/...)
  static final RegExp _androidStoragePathRegex = RegExp(
    r'(?:/storage/emulated/\d+/|/sdcard/|/mnt/sdcard/)[^\s\n\r:)]*',
    caseSensitive: false,
  );

  // Regex for Android internal data paths (e.g. /data/user/0/com.veil.player/...)
  static final RegExp _androidInternalDataRegex = RegExp(
    r'/data/(?:user/\d+|data)/[a-zA-Z0-9._-]+/[^\s\n\r:)]*',
    caseSensitive: false,
  );

  // Regex for Windows user directory paths (e.g. C:\Users\john_doe\... or C:/Users/john_doe/...)
  static final RegExp _windowsUserPathRegex = RegExp(
    r'[a-zA-Z]:[/\\]Users[/\\][^/\\\s\n\r]+[/\\]',
    caseSensitive: false,
  );

  // Regex for macOS user directory paths (e.g. /Users/john_doe/...)
  static final RegExp _macUserPathRegex = RegExp(
    r'/Users/[^/\s\n\r]+/',
    caseSensitive: false,
  );

  // Regex for Linux user directory paths (e.g. /home/john_doe/...)
  static final RegExp _linuxUserPathRegex = RegExp(
    r'/home/[^/\s\n\r]+/',
    caseSensitive: false,
  );

  // Regex matching media file extensions
  static final RegExp _mediaFileExtensionRegex = RegExp(
    r'[^\s\n\r\\/]+\.(?:mkv|mp4|avi|mov|webm|ts|mts|m2ts|flv|3gp|3g2|3gpp|ogv|wmv|rm|rmvb|mpeg|mpg|vob|m4v|f4v|srt|vtt|ass|ssa|sub|idx|txt)',
    caseSensitive: false,
  );

  // Regex matching IP addresses
  static final RegExp _ipAddressRegex = RegExp(
    r'\b(?:\d{1,3}\.){3}\d{1,3}\b',
  );

  /// Central sanitization entry point for all diagnostic strings.
  static String sanitize(String input) {
    if (input.isEmpty) return input;

    String sanitized = input;

    // 1. Sanitize IP addresses if any
    sanitized = sanitized.replaceAll(_ipAddressRegex, '<IP_REDACTED>');

    // 2. Sanitize Android storage paths
    sanitized = sanitized.replaceAllMapped(_androidStoragePathRegex, (match) {
      final matchedStr = match.group(0) ?? '';
      return _anonymizePath(matchedStr);
    });

    // 3. Sanitize Android internal app data paths
    sanitized = sanitized.replaceAllMapped(_androidInternalDataRegex, (match) {
      return '<APP_PRIVATE_DIR>';
    });

    // 4. Sanitize OS User directory paths
    sanitized = sanitized.replaceAllMapped(_windowsUserPathRegex, (match) {
      final matched = match.group(0) ?? '';
      return matched.contains('/') ? 'C:/Users/<USER>/' : r'C:\Users\<USER>\';
    });
    sanitized = sanitized.replaceAll(_macUserPathRegex, '/Users/<USER>/');
    sanitized = sanitized.replaceAll(_linuxUserPathRegex, '/home/<USER>/');

    // 5. Sanitize any remaining loose media filenames
    sanitized = sanitized.replaceAllMapped(_mediaFileExtensionRegex, (match) {
      final fileStr = match.group(0) ?? '';
      // Retain file extension for technical context (e.g., .mkv, .mp4)
      final dotIndex = fileStr.lastIndexOf('.');
      if (dotIndex != -1) {
        final ext = fileStr.substring(dotIndex + 1).toUpperCase();
        return '<MEDIA_FILE.$ext>';
      }
      return '<MEDIA_FILE>';
    });

    return sanitized;
  }

  /// Sanitizes stack traces, preserving source symbol names and line numbers
  /// while stripping local environment paths and user filenames.
  static String sanitizeStackTrace(String stackTrace) {
    if (stackTrace.isEmpty) return stackTrace;

    final lines = stackTrace.split('\n');
    final sanitizedLines = lines.map((line) {
      // Retain Flutter / Dart package line markers (e.g. package:veil_player/...)
      // But sanitize any absolute file paths embedded in stack trace frames.
      return sanitize(line);
    });

    return sanitizedLines.join('\n');
  }

  /// Converts a path to an anonymized safe representation.
  static String _anonymizePath(String fullPath) {
    final dotIndex = fullPath.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < fullPath.length - 1) {
      final ext = fullPath.substring(dotIndex + 1).toUpperCase();
      return '<MEDIA_FILE.$ext>';
    }
    return '<MEDIA_FILE>';
  }

  /// Formats safe technical media metadata for report output without exposing file paths.
  static Map<String, String> formatSafeMediaMetadata({
    required String? rawPath,
    Duration? duration,
    int? width,
    int? height,
    String? videoCodec,
    String? audioCodec,
    String? container,
    String? hwDecoder,
    int? positionMs,
    double? speed,
    String? sessionAlias,
  }) {
    final map = <String, String>{};

    final alias = sessionAlias ?? 'MEDIA_1';
    final containerType = container ?? _inferContainer(rawPath) ?? 'Unknown';

    map['Media Identifier'] = '<MEDIA_FILE> [$alias]';
    map['Container Format'] = containerType.toUpperCase();

    if (width != null && height != null && width > 0 && height > 0) {
      map['Resolution'] = '${width}x$height';
    } else {
      map['Resolution'] = 'Unknown';
    }

    if (duration != null && duration.inMilliseconds > 0) {
      map['Duration'] = _formatDuration(duration);
    } else {
      map['Duration'] = 'Unknown';
    }

    if (positionMs != null && positionMs > 0) {
      map['Playback Position'] = _formatDuration(Duration(milliseconds: positionMs));
    } else {
      map['Playback Position'] = '00:00:00';
    }

    map['Video Codec'] = videoCodec ?? 'Unknown';
    map['Audio Codec'] = audioCodec ?? 'Unknown';
    map['Hardware Decoder'] = hwDecoder ?? 'Not Active / Default';

    if (speed != null) {
      map['Playback Speed'] = '${speed.toStringAsFixed(1)}x';
    }

    return map;
  }

  static String? _inferContainer(String? path) {
    if (path == null || path.isEmpty) return null;
    final dot = path.lastIndexOf('.');
    if (dot != -1 && dot < path.length - 1) {
      return path.substring(dot + 1).toLowerCase();
    }
    return null;
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
