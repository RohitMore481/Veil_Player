import 'package:flutter/cupertino.dart';

/// Veil's custom page route — hardware-accelerated native Cupertino transition.
/// Used for all Navigator.push calls across the app.
/// Provides native swipe-to-back gesture support with 120Hz-smooth transitions.
class VeilPageRoute<T> extends CupertinoPageRoute<T> {
  VeilPageRoute({required super.builder, super.settings});
}
