import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_button.dart';
import '../../../core/widgets/veil_empty_state.dart';
import '../providers/audio_pinned_folders_provider.dart';

class ManageAudioPinnedFoldersDialog extends ConsumerWidget {
  const ManageAudioPinnedFoldersDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedPaths = ref.watch(audioPinnedFoldersProvider);
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: 0.95 + (0.05 * value),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage Pinned Audio Folders',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Drag to reorder your pinned audio folders.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              if (pinnedPaths.isEmpty)
                const VeilEmptyState(
                  icon: Icons.push_pin_outlined,
                  title: 'No pinned folders',
                  description: 'Pin folders to access them quickly from Quick Access.',
                  iconSize: 36,
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      canvasColor: Colors.transparent,
                    ),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: pinnedPaths.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        ref
                            .read(audioPinnedFoldersProvider.notifier)
                            .reorder(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final path = pinnedPaths[index];
                        final name = path.split(RegExp(r'[/\\]')).lastWhere(
                              (s) => s.isNotEmpty,
                              orElse: () => 'Folder',
                            );
                        return Container(
                          key: ValueKey(path),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? const Color(0xFF1E1E1E)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFF2C2C2C)
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            leading: IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () {
                                ref
                                    .read(audioPinnedFoldersProvider.notifier)
                                    .togglePin(path);
                              },
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            trailing: const Icon(Icons.drag_handle_rounded,
                                color: Colors.grey),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: VeilButton(
                  label: 'Done',
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
