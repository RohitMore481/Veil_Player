import 'package:flutter/material.dart';

class BrightnessVolumeOverlay extends StatelessWidget {
  final bool isVolume;
  final double value; // 0.0 to 1.0

  const BrightnessVolumeOverlay({
    super.key,
    required this.isVolume,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return Semantics(
      label: isVolume
          ? 'Volume level, ${(value * 100).toInt()}%'
          : 'Brightness level, ${(value * 100).toInt()}%',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E1E1E), width: 1),
        ),
        width: 64,
        height: 180,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              isVolume
                  ? (value == 0
                        ? Icons.volume_mute_rounded
                        : value < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded)
                  : Icons.brightness_medium_rounded,
              color: Colors.white,
              size: 24,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 6.0,
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Inactive track
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Active level track
                    FractionallySizedBox(
                      heightFactor: value.clamp(0.0, 1.0),
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
