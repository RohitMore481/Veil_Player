import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralizes MethodChannel callbacks to allow multiple dynamic subscribers.
///
/// Prevents components from overwriting the single root `setMethodCallHandler`.
class MethodChannelDispatcher {
  static const _channel = MethodChannel('veil_player/media');
  static final List<Future<dynamic> Function(MethodCall)> _listeners = [];
  static bool _initialized = false;

  /// Initializes the main channel listener. Called once on startup.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      // Dispatch to all registered listeners
      for (final listener in List.from(_listeners)) {
        try {
          await listener(call);
        } catch (e, stack) {
          debugPrint(
            '[MethodChannelDispatcher] Error executing listener: $e\n$stack',
          );
        }
      }
      return null;
    });
  }

  /// Adds a callback listener for method calls.
  static void addListener(Future<dynamic> Function(MethodCall) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// Removes a registered listener.
  static void removeListener(Future<dynamic> Function(MethodCall) listener) {
    _listeners.remove(listener);
  }
}
