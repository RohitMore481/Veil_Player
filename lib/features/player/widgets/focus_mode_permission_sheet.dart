import 'package:flutter/material.dart';
import '../../../core/widgets/veil_bottom_sheet.dart';
import '../../../core/widgets/veil_button.dart';
import '../../library/services/media_service.dart';

class FocusModePermissionSheet {
  static void show(BuildContext context) {
    VeilBottomSheet.show(
      context: context,
      title: 'Focus Mode (Cinema Mode)',
      subtitle: 'Distraction-free viewing experience',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.do_not_disturb_on_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Focus Mode requires notification control permission to reduce interruptions while watching.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Phone calls, alarms, and emergency alerts will NOT be silenced.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
              VeilButton(
                label: 'Enable Focus Mode',
                icon: Icons.settings_rounded,
                onTap: () {
                  Navigator.pop(context);
                  MediaService().openNotificationPolicySettings();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
