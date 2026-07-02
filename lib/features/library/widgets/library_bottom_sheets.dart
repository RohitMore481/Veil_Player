import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';
import '../providers/media_provider.dart';
import '../../file_operations/providers/pending_operation_provider.dart';
import '../providers/selection_provider.dart';

void showFolderActionsBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required FolderItem folder,
}) {
  final theme = Theme.of(context);
  final isPinned = ref
      .read(pinnedFoldersProvider.notifier)
      .isPinned(folder.path);

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
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    folder.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF161616)
                  : const Color(0xFFE5E7EB),
              height: 20,
            ),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                isPinned ? 'Unpin from Quick Access' : 'Pin to Quick Access',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                ref.read(pinnedFoldersProvider.notifier).togglePin(folder.path);
                ref.invalidate(foldersProvider);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.edit_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Rename Folder',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _showRenameFolderDialog(context, ref, folder);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.refresh_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Refresh Folder',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () async {
                Navigator.pop(context);
                final success = await ref
                    .read(mediaRepositoryProvider)
                    .refreshFolder(folder.path);
                if (!context.mounted) return;
                if (success) {
                  ref.invalidate(foldersProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Folder refreshed'),
                      backgroundColor: theme.brightness == Brightness.dark
                          ? const Color(0xFF111111)
                          : const Color(0xFFF3F4F6),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.visibility_off_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Hide Folder',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _showHideFolderDialog(context, ref, folder);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete Folder',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.pop(context);
                _showDeleteFolderDialog(context, ref, folder);
              },
            ),
          ],
        ),
      );
    },
  );
}

void _showRenameFolderDialog(
  BuildContext context,
  WidgetRef ref,
  FolderItem folder,
) {
  final theme = Theme.of(context);
  final controller = TextEditingController(text: folder.name);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFE5E7EB),
            width: 1.2,
          ),
        ),
        title: Text(
          'Rename Folder',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'New Folder Name',
            labelStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Rename',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != folder.name) {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                final manager = ref.read(pendingOperationManagerProvider);
                final result = await manager.execute(
                  RenameFolderOp(path: folder.path, newName: newName),
                );
                if (!context.mounted) return;
                if (result.$1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(result.$2),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (result.$2.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.$2),
                      backgroundColor: theme.brightness == Brightness.dark
                          ? const Color(0xFF111111)
                          : const Color(0xFFF3F4F6),
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

void _showHideFolderDialog(
  BuildContext context,
  WidgetRef ref,
  FolderItem folder,
) {
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFE5E7EB),
            width: 1.2,
          ),
        ),
        title: Text(
          'Hide Folder',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Hiding this folder will write a .nomedia file inside it. The media scanner will exclude this folder and its videos from the player. You can unhide it using a file manager by deleting the .nomedia file.\n\nProceed?',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Hide',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(mediaRepositoryProvider)
                  .hideFolder(folder.path);
              if (!context.mounted) return;
              if (success) {
                ref.invalidate(foldersProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Folder "${folder.name}" is now hidden'),
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF111111)
                        : const Color(0xFFF3F4F6),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Failed to hide folder'),
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF111111)
                        : const Color(0xFFF3F4F6),
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

void _showDeleteFolderDialog(
  BuildContext context,
  WidgetRef ref,
  FolderItem folder,
) {
  final theme = Theme.of(context);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFE5E7EB),
            width: 1.2,
          ),
        ),
        title: const Text(
          'Delete Folder',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${folder.name}" and all of its ${folder.count} videos?\n\nThis action cannot be undone and will delete files physically on your storage.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final manager = ref.read(pendingOperationManagerProvider);
              final result = await manager.execute(
                DeleteFolderOp(path: folder.path),
              );
              if (!context.mounted) return;
              if (result.$2.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.$2),
                    backgroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF111111)
                        : const Color(0xFFF3F4F6),
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
  final theme = Theme.of(context);

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
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  const SizedBox(height: 4),
                  Text(
                    video.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF161616)
                  : const Color(0xFFE5E7EB),
              height: 20,
            ),
            ListTile(
              leading: Icon(
                Icons.check_circle_outline_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Select',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                final selectionNotifier = ref.read(
                  selectionModeProvider.notifier,
                );
                final selectedNotifier = ref.read(
                  selectedVideosProvider.notifier,
                );
                selectionNotifier.state = true;
                selectedNotifier.toggle(video.id);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.edit_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Rename',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _showRenameVideoDialog(context, ref, video, currentFolderName);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.share_rounded,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                'Share',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(mediaRepositoryProvider).shareVideo(video.path);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.info_outline_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                'Properties',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _showVideoPropertiesDialog(context, ref, video);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.pop(context);
                final manager = ref.read(pendingOperationManagerProvider);
                final result = await manager.execute(
                  DeleteVideoOp(
                    id: video.id,
                    path: video.path,
                    folderName: currentFolderName,
                  ),
                );
                if (!context.mounted) return;
                if (result.$1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(result.$2),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (result.$2.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.$2),
                      backgroundColor: theme.brightness == Brightness.dark
                          ? const Color(0xFF111111)
                          : const Color(0xFFF3F4F6),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      );
    },
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
          side: BorderSide(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFE5E7EB),
            width: 1.2,
          ),
        ),
        title: Text(
          'Rename Video',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'New Name',
            labelStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Rename',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != video.title) {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
                final manager = ref.read(pendingOperationManagerProvider);
                final result = await manager.execute(
                  RenameVideoOp(
                    id: video.id,
                    path: video.path,
                    newName: newName,
                    folderName: currentFolderName,
                  ),
                );
                if (!context.mounted) return;
                if (result.$1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(result.$2),
                        ],
                      ),
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (result.$2.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.$2),
                      backgroundColor: theme.brightness == Brightness.dark
                          ? const Color(0xFF111111)
                          : const Color(0xFFF3F4F6),
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

void _showVideoPropertiesDialog(
  BuildContext context,
  WidgetRef ref,
  VideoItem video,
) {
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
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                      ),
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
              side: BorderSide(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFE5E7EB),
                width: 1.2,
              ),
            ),
            title: Text(
              'Properties',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
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
                      infoRow(
                        'Resolution',
                        '${metadata['width']}x${metadata['height']}',
                      ),
                    if (metadata['bitrate'] != null)
                      infoRow(
                        'Bitrate',
                        '${(int.parse(metadata['bitrate'].toString()) / 1000).toStringAsFixed(0)} kbps',
                      ),
                    if (metadata['frameRate'] != null)
                      infoRow(
                        'Frame Rate',
                        '${double.tryParse(metadata['frameRate'].toString())?.toStringAsFixed(1) ?? metadata['frameRate']} fps',
                      ),
                    if (metadata['extension'] != null)
                      infoRow(
                        'Format',
                        metadata['extension'].toString().toUpperCase(),
                      ),
                  ] else if (snapshot.connectionState ==
                      ConnectionState.waiting) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
    },
  );
}
