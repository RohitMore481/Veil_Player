import 'package:flutter/material.dart';

class SeekGestureOverlay extends StatelessWidget {
  final Duration targetPosition;
  final Duration totalDuration;
  final int deltaSeconds;

  const SeekGestureOverlay({
    super.key,
    required this.targetPosition,
    required this.totalDuration,
    required this.deltaSeconds,
  });

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return "${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
    return "${twoDigits(minutes)}:${twoDigits(seconds)}";
  }

  String _formatDelta(int sec) {
    final sign = sec >= 0 ? '+' : '-';
    final absSec = sec.abs();
    final minutes = absSec ~/ 60;
    final remainingSec = absSec % 60;

    if (minutes > 0) {
      if (remainingSec > 0) {
        return '$sign${minutes}m ${remainingSec}s';
      }
      return '$sign${minutes}m';
    }
    return '$sign${remainingSec}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForward = deltaSeconds >= 0;

    final progressFactor = totalDuration.inMilliseconds > 0
        ? (targetPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E1E1E), width: 1),
        ),
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isForward
                      ? Icons.fast_forward_rounded
                      : Icons.fast_rewind_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDelta(deltaSeconds),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${_formatDuration(targetPosition)} / ${_formatDuration(totalDuration)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progressFactor,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
