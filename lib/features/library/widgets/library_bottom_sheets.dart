import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';
import '../providers/media_provider.dart';
import '../../file_operations/providers/pending_operation_provider.dart';
import '../../file_operations/providers/file_clipboard_provider.dart';
import '../providers/selection_provider.dart';
import '../../folders/widgets/manage_pinned_folders_dialog.dart';
import '../../../core/widgets/veil_bottom_sheet.dart';

void showFolderActionsBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required FolderItem folder,
}) {
  final isPinned = ref.read(pinnedFoldersProvider.notifier).isPinned(folder.path);
  final clipboard = ref.read(fileClipboardProvider);

  VeilBottomSheet.show(
    context: context,
    title: folder.name,
    subtitle: folder.path,
    children: [
      if (clipboard.isNotEmpty)
        VeilBottomSheetTile(
          leadingIcon: Icons.content_paste_rounded,
          title: 'Paste into this folder (${clipboard.count} item${clipboard.count > 1 ? 's' : ''})',
          onTap: () async {
            Navigator.pop(context);
            await _pasteIntoFolder(context, ref, folder.path, folder.name);
          },
        ),
      VeilBottomSheetTile(
        leadingIcon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        title: isPinned ? 'Unpin from Quick Access' : 'Pin to Quick Access',
        onTap: () {
          Navigator.pop(context);
          ref.read(pinnedFoldersProvider.notifier).togglePin(folder.path);
          ref.invalidate(foldersProvider);
        },
      ),
      if (isPinned)
        VeilBottomSheetTile(
          leadingIcon: Icons.low_priority_rounded,
          title: 'Manage Pinned Folders',
          onTap: () {
            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (context) => const ManagePinnedFoldersDialog(),
            );
          },
        ),
      VeilBottomSheetTile(
        leadingIcon: Icons.edit_rounded,
        title: 'Rename Folder',
        onTap: () {
          Navigator.pop(context);
          _showRenameFolderDialog(context, ref, folder);
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.refresh_rounded,
        title: 'Refresh Folder',
        onTap: () async {
          Navigator.pop(context);
          final success = await ref.read(mediaRepositoryProvider).refreshFolder(folder.path);
          if (!context.mounted) return;
          if (success) {
            ref.invalidate(foldersProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Folder refreshed'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.visibility_off_rounded,
        title: 'Hide Folder',
        onTap: () {
          Navigator.pop(context);
          _showHideFolderDialog(context, ref, folder);
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.delete_rounded,
        title: 'Delete Folder',
        onTap: () async {
          Navigator.pop(context);
          _showDeleteFolderDialog(context, ref, folder);
        },
      ),
    ],
  );
}

void _showRenameFolderDialog(BuildContext context, WidgetRef ref, FolderItem folder) {
  final theme = Theme.of(context);
  final controller = TextEditingController(text: folder.name);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB), width: 1.2),
        ),
        title: Text(
          'Rename Folder',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'New Folder Name',
            labelStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Rename', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != folder.name) {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                final manager = ref.read(pendingOperationManagerProvider);
                final result = await manager.execute(RenameFolderOp(path: folder.path, newName: newName));
                if (!context.mounted) return;
                if (result.$1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Text(result.$2),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (result.$2.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.$2),
                      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFF3F4F6),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ],
      );
    },
  );
}

void _showHideFolderDialog(BuildContext context, WidgetRef ref, FolderItem folder) {
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB), width: 1.2),
        ),
        title: Text(
          'Hide Folder',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Hiding this folder will write a .nomedia file inside it. The media scanner will exclude this folder and its videos from the player. You can unhide it using a file manager by deleting the .nomedia file.\n\nProceed?',
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Hide', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref.read(mediaRepositoryProvider).hideFolder(folder.path);
              if (!context.mounted) return;
              if (success) {
                ref.invalidate(foldersProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Folder "${folder.name}" is now hidden'),
                    backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFF3F4F6),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Failed to hide folder'),
                    backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFF3F4F6),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      );
    },
  );
}

void _showDeleteFolderDialog(BuildContext context, WidgetRef ref, FolderItem folder) {
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB), width: 1.2),
        ),
        title: const Text(
          'Delete Folder',
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${folder.name}" and all of its ${folder.count} videos?\n\nThis action cannot be undone and will delete files physically on your storage.',
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(context);
              final manager = ref.read(pendingOperationManagerProvider);
              final result = await manager.execute(DeleteFolderOp(path: folder.path));
              if (!context.mounted) return;
              if (result.$2.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.$2),
                    backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFF3F4F6),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      );
    },
  );
}

void showVideoActionsBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required VideoItem video,
  required String currentFolderName,
}) {
  VeilBottomSheet.show(
    context: context,
    title: video.title,
    subtitle: video.path,
    children: [
      VeilBottomSheetTile(
        leadingIcon: Icons.check_circle_outline_rounded,
        title: 'Select',
        onTap: () {
          Navigator.pop(context);
          final selectionNotifier = ref.read(selectionModeProvider.notifier);
          final selectedNotifier = ref.read(selectedVideosProvider.notifier);
          selectionNotifier.state = true;
          selectedNotifier.toggle(video.id);
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.edit_rounded,
        title: 'Rename',
        onTap: () {
          Navigator.pop(context);
          _showRenameVideoDialog(context, ref, video, currentFolderName);
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.content_cut_rounded,
        title: 'Cut / Move',
        onTap: () {
          Navigator.pop(context);
          ref.read(fileClipboardProvider.notifier).moveSingle(video, currentFolderName);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.content_cut_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text('"${video.title}" ready to move. Open a folder to paste.')),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ),
          );
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.content_copy_rounded,
        title: 'Copy',
        onTap: () {
          Navigator.pop(context);
          ref.read(fileClipboardProvider.notifier).copySingle(video, currentFolderName);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.content_copy_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text('"${video.title}" copied. Open a folder to paste.')),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ),
          );
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.share_rounded,
        title: 'Share',
        onTap: () async {
          Navigator.pop(context);
          await ref.read(mediaRepositoryProvider).shareVideo(video.path);
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.info_outline_rounded,
        title: 'Properties',
        onTap: () {
          Navigator.pop(context);
          _showVideoPropertiesDialog(context, ref, video);
        },
      ),
      VeilBottomSheetTile(
        leadingIcon: Icons.delete_rounded,
        title: 'Delete',
        onTap: () async {
          Navigator.pop(context);
          final manager = ref.read(pendingOperationManagerProvider);
          final result = await manager.execute(
            DeleteVideoOp(id: video.id, path: video.path, folderName: currentFolderName),
          );
          if (!context.mounted) return;
          if (result.$1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(result.$2),
                  ],
                ),
                backgroundColor: const Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 3),
              ),
            );
          } else if (result.$2.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.$2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    ],
  );
}

void _showRenameVideoDialog(
  BuildContext context,
  WidgetRef ref,
  VideoItem video,
  String currentFolderName,
) {
  final theme = Theme.of(context);
  final controller = TextEditingController(text: video.title);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB), width: 1.2),
        ),
        title: Text(
          'Rename Video',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'New Name',
            labelStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Rename', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != video.title) {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                final manager = ref.read(pendingOperationManagerProvider);
                final result = await manager.execute(
                  RenameVideoOp(id: video.id, path: video.path, newName: newName, folderName: currentFolderName),
                );
                if (!context.mounted) return;
                if (result.$1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Text(result.$2),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (result.$2.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.$2),
                      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF111111) : const Color(0xFFF3F4F6),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ],
      );
    },
  );
}

void _showVideoPropertiesDialog(BuildContext context, WidgetRef ref, VideoItem video) {
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (context) {
      return FutureBuilder<Map<dynamic, dynamic>?>(
        future: ref.read(mediaRepositoryProvider).getVideoMetadata(video.path),
        builder: (context, snapshot) {
          final metadata = snapshot.data;
          
          Widget infoRow(String label, String value) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      label,
                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB), width: 1.2),
            ),
            title: Text(
              'Properties',
              style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  infoRow('Title', video.title),
                  infoRow('Path', video.path),
                  infoRow('Size', video.formattedSize),
                  infoRow('Duration', video.formattedDuration),
                  if (metadata != null) ...[
                    if (metadata['width'] != null && metadata['height'] != null)
                      infoRow('Resolution', '${metadata['width']}x${metadata['height']}'),
                    if (metadata['bitrate'] != null)
                      infoRow('Bitrate', '${(int.parse(metadata['bitrate'].toString()) / 1000).toStringAsFixed(0)} kbps'),
                    if (metadata['frameRate'] != null)
                      infoRow('Frame Rate', '${double.tryParse(metadata['frameRate'].toString())?.toStringAsFixed(1) ?? metadata['frameRate']} fps'),
                    if (metadata['extension'] != null)
                      infoRow('Format', metadata['extension'].toString().toUpperCase()),
                  ] else if (snapshot.connectionState == ConnectionState.waiting) ...[
                    const SizedBox(height: 12),
                    Center(child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 1.5)),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
    },
  );
}

void showContinueWatchingInfoSheet({
  required BuildContext context,
  required WidgetRef ref,
  required VideoItem video,
  required int positionMs,
  required int durationMs,
  required double progress,
}) {
  final theme = Theme.of(context);

  String formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minStr:$secStr';
    }
    return '$minStr:$secStr';
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 150),
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInQuart,
    ),
    builder: (context) {
      return FutureBuilder<Map<dynamic, dynamic>?>(
        future: ref.read(mediaRepositoryProvider).getVideoMetadata(video.path),
        builder: (context, snapshot) {
          final metadata = snapshot.data;

          String folderLocation = video.path;
          try {
            final file = File(video.path);
            folderLocation = file.parent.path;
          } catch (_) {}

          String fileSizeStr = video.formattedSize;
          if (fileSizeStr.isEmpty || fileSizeStr == '0 B') {
            if (metadata != null && metadata['size'] != null) {
              final sizeBytes = int.tryParse(metadata['size'].toString()) ?? 0;
              if (sizeBytes > 1024 * 1024 * 1024) {
                fileSizeStr = '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
              } else if (sizeBytes > 1024 * 1024) {
                fileSizeStr = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
              } else if (sizeBytes > 0) {
                fileSizeStr = '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
              }
            }
          }

          String resolutionStr = 'Unknown';
          if (metadata != null && metadata['width'] != null && metadata['height'] != null) {
            resolutionStr = '${metadata['width']}x${metadata['height']}';
          }

          String formatStr = 'Unknown';
          if (metadata != null && metadata['extension'] != null && metadata['extension'].toString().isNotEmpty) {
            formatStr = metadata['extension'].toString().toUpperCase();
          } else {
            final ext = video.path.split('.').last;
            if (ext.isNotEmpty && ext != video.path) {
              formatStr = ext.toUpperCase();
            }
          }

          final pct = (progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0);
          final lastWatchedStr = '${formatMs(positionMs)} ($pct%)';

          Widget infoRow(String label, String value, {IconData? icon}) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(
                    width: 120,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E7EB),
                  width: 1,
                ),
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Continue Watching Info',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Divider(
                    color: theme.brightness == Brightness.dark ? const Color(0xFF161616) : const Color(0xFFE5E7EB),
                    height: 24,
                  ),
                  infoRow('Video Name', video.title, icon: Icons.movie_outlined),
                  infoRow('Folder Location', folderLocation, icon: Icons.folder_open_outlined),
                  infoRow('Duration', durationMs > 0 ? formatMs(durationMs) : video.formattedDuration, icon: Icons.timer_outlined),
                  infoRow('File Size', fileSizeStr, icon: Icons.sd_storage_outlined),
                  infoRow('Resolution', resolutionStr, icon: Icons.aspect_ratio_rounded),
                  infoRow('Format / Codec', formatStr, icon: Icons.video_file_outlined),
                  infoRow('Last Watched', lastWatchedStr, icon: Icons.history_toggle_off_rounded),
                  if (snapshot.connectionState == ConnectionState.waiting) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> _pasteIntoFolder(
  BuildContext context,
  WidgetRef ref,
  String targetPath,
  String targetName,
) async {
  final clipboard = ref.read(fileClipboardProvider);
  if (clipboard.isEmpty) return;

  if (clipboard.isMove && clipboard.items.length == 1 && clipboard.items.first.sourceFolderName == targetName) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File is already in this folder.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final manager = ref.read(pendingOperationManagerProvider);
  (bool, String) result;

  if (clipboard.items.length == 1) {
    final item = clipboard.items.first;
    if (clipboard.isMove) {
      result = await manager.execute(MoveVideoOp(
        id: item.id,
        path: item.path,
        targetFolder: targetPath,
        targetFolderName: targetName,
        sourceFolderName: item.sourceFolderName,
      ));
    } else {
      result = await manager.execute(CopyVideoOp(
        id: item.id,
        path: item.path,
        targetFolder: targetPath,
        targetFolderName: targetName,
        sourceFolderName: item.sourceFolderName,
      ));
    }
  } else {
    if (clipboard.isMove) {
      result = await manager.execute(BatchMoveVideoOp(
        ids: clipboard.ids,
        paths: clipboard.paths,
        targetFolder: targetPath,
        targetFolderName: targetName,
        sourceFolderNames: clipboard.sourceFolderNames,
      ));
    } else {
      result = await manager.execute(BatchCopyVideoOp(
        paths: clipboard.paths,
        targetFolder: targetPath,
        targetFolderName: targetName,
        sourceFolderNames: clipboard.sourceFolderNames,
      ));
    }
  }

  if (!context.mounted) return;

  if (result.$1) {
    ref.read(fileClipboardProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(result.$2)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  } else if (result.$2.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.$2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}


