import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veil_player/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Mock the MethodChannel for native platform interactions
    const channel = MethodChannel('veil_player/media');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      switch (methodCall.method) {
        case 'checkPermission':
          return 'granted';
        case 'getFolders':
          return <Map<String, dynamic>>[];
        case 'getAllPlaybackPositions':
          return <Map<String, dynamic>>[];
        case 'getPlayerSetting':
          final key = methodCall.arguments['key'];
          if (key == 'theme_accent') return 'Emerald';
          if (key == 'amoled_pure_black') return true;
          return null;
        default:
          return null;
      }
    });

    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: VeilApp()));

    // Let microtasks and asynchronous tasks finish (e.g. permission check)
    await tester.pumpAndSettle();

    // Verify that our library screen starts and title exists.
    expect(find.text('VEIL'), findsOneWidget);
  });
}
