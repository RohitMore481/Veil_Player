import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/diagnostics/diagnostic_event.dart';
import 'package:veil_player/diagnostics/diagnostic_event_buffer.dart';

void main() {
  group('DiagnosticEventBuffer Tests', () {
    test('Enforces circular capacity limit', () {
      final buffer = DiagnosticEventBuffer(capacity: 100);

      for (int i = 1; i <= 150; i++) {
        buffer.add(DiagnosticEvent(
          timestamp: DateTime.now(),
          category: DiagnosticCategory.player,
          severity: DiagnosticSeverity.info,
          event: 'Event #$i',
        ));
      }

      expect(buffer.length, 100);
      final events = buffer.getEvents();
      expect(events.first.event, 'Event #51');
      expect(events.last.event, 'Event #150');
    });

    test('Filters events by category and session ID', () {
      final buffer = DiagnosticEventBuffer(capacity: 50);

      buffer.add(DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.player,
        severity: DiagnosticSeverity.info,
        event: 'Player start',
        playbackSessionId: 'SESSION_A',
      ));

      buffer.add(DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.audio,
        severity: DiagnosticSeverity.info,
        event: 'Audio focus gained',
        playbackSessionId: 'SESSION_A',
      ));

      buffer.add(DiagnosticEvent(
        timestamp: DateTime.now(),
        category: DiagnosticCategory.player,
        severity: DiagnosticSeverity.info,
        event: 'Player start B',
        playbackSessionId: 'SESSION_B',
      ));

      final sessionAEvents = buffer.getRecentEvents(playbackSessionId: 'SESSION_A');
      expect(sessionAEvents.length, 2);
      expect(sessionAEvents.every((e) => e.playbackSessionId == 'SESSION_A'), isTrue);

      final audioEvents = buffer.getRecentEvents(categoryFilter: DiagnosticCategory.audio);
      expect(audioEvents.length, 1);
      expect(audioEvents.first.event, 'Audio focus gained');
    });

    test('Formats event string correctly', () {
      final dt = DateTime(2026, 10, 9, 14, 30, 45);
      final event = DiagnosticEvent(
        timestamp: dt,
        category: DiagnosticCategory.player,
        severity: DiagnosticSeverity.warning,
        event: 'Decoder glitch',
        playbackSessionId: 'MEDIA_1',
      );

      final str = event.toFormattedString();
      expect(str, contains('14:30:45'));
      expect(str, contains('[PLAYER]'));
      expect(str, contains('[WARNING]'));
      expect(str, contains('[MEDIA_1]'));
      expect(str, contains('Decoder glitch'));
    });
  });
}
