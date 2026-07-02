import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/media_diagnostics.dart';
import '../models/playback_error.dart';
import '../registry/codec_registry.dart';
import '../registry/format_support_service.dart';
import '../services/codec_detector.dart';
import '../services/media_diagnostics_service.dart';

// ── Core service providers ─────────────────────────────────────────────────────

/// The [CodecRegistry] singleton as a Riverpod provider.
///
/// The registry is initialised once and shared across the app.
/// Future codec packs call [CodecRegistry.instance.registerCodecPack()] at
/// app startup — no provider rebinding needed.
final codecRegistryProvider = Provider<CodecRegistry>((ref) {
  return CodecRegistry.instance;
});

/// The [FormatSupportService] as a Riverpod provider.
final formatSupportServiceProvider = Provider<FormatSupportService>((ref) {
  return FormatSupportService(registry: ref.watch(codecRegistryProvider));
});

/// The [CodecDetector] as a Riverpod provider.
final codecDetectorProvider = Provider<CodecDetector>((ref) {
  return const CodecDetector();
});

/// The [MediaDiagnosticsService] as a Riverpod provider.
final mediaDiagnosticsServiceProvider = Provider<MediaDiagnosticsService>((
  ref,
) {
  return MediaDiagnosticsService(
    detector: ref.watch(codecDetectorProvider),
    supportService: ref.watch(formatSupportServiceProvider),
  );
});

// ── Session-scoped diagnostics state ──────────────────────────────────────────

/// Holds the [MediaDiagnostics] snapshot for the current player session.
///
/// Set by [PlayerScreen] after calling [MediaDiagnosticsService.analyze()].
/// Reset to null when the player closes.
final currentDiagnosticsProvider = StateProvider<MediaDiagnostics?>(
  (ref) => null,
);

/// Holds the current [PlaybackError] if playback has failed.
///
/// Set by [PlayerScreen] when a playback error is detected.
/// Reset to null when a new file opens successfully.
final currentPlaybackErrorProvider = StateProvider<PlaybackError?>(
  (ref) => null,
);
