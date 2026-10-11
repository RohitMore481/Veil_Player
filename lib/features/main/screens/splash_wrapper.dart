import 'dart:io';
import 'package:flutter/material.dart';
import 'splash_screen.dart';
import 'main_navigation_screen.dart';

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

  @override
  State<SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> {
  // Static variable persists across resume/background events for the lifetime of Dart VM process
  static bool _hasPlayedSplash = false;
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    _showSplash = !_hasPlayedSplash && !isTest;
    if (_showSplash) {
      _hasPlayedSplash = true;
    }
  }

  void _onSplashFinished() {
    if (mounted) {
      setState(() {
        _showSplash = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black, // Pure AMOLED black background during the transition switcher
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200), // Smooth 200ms fade transition
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        child: _showSplash
            ? SplashScreen(
                key: const ValueKey('splash_screen'),
                onFinished: _onSplashFinished,
              )
            : const MainNavigationScreen(
                key: ValueKey('main_navigation_screen'),
              ),
      ),
    );
  }
}
