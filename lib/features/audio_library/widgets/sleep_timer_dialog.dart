import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/audio_player_provider.dart';

class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(audioPlayerProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final options = [
      {'label': 'Turn off timer', 'duration': null, 'endOfTrack': false},
      {'label': 'End of current track', 'duration': null, 'endOfTrack': true},
      {'label': '15 minutes', 'duration': const Duration(minutes: 15), 'endOfTrack': false},
      {'label': '30 minutes', 'duration': const Duration(minutes: 30), 'endOfTrack': false},
      {'label': '45 minutes', 'duration': const Duration(minutes: 45), 'endOfTrack': false},
      {'label': '60 minutes', 'duration': const Duration(minutes: 60), 'endOfTrack': false},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14171A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.bedtime_rounded, color: primary, size: 22),
                const SizedBox(width: 12),
                Text(
                  'Sleep Timer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...options.map((opt) {
            final isTurnOff = opt['duration'] == null && opt['endOfTrack'] == false;
            final isEndOfTrack = opt['endOfTrack'] == true;
            final label = opt['label'] as String;
            final duration = opt['duration'] as Duration?;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: isTurnOff ? Colors.redAccent : (isDark ? Colors.white : Colors.black87),
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white30 : Colors.black26,
                size: 20,
              ),
              onTap: () {
                if (isTurnOff) {
                  notifier.cancelSleepTimer();
                } else if (isEndOfTrack) {
                  notifier.setSleepTimer(null, endOfTrack: true);
                } else {
                  notifier.setSleepTimer(duration);
                }
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
