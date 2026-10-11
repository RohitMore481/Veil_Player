import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/file_clipboard_provider.dart';
import '../providers/pending_operation_provider.dart';
import '../../library/providers/media_provider.dart';

class FileClipboardBar extends ConsumerStatefulWidget {
  final String? currentFolderName;
  final String? currentFolderPath;
  final double bottomPadding;

  const FileClipboardBar({
    super.key,
    this.currentFolderName,
    this.currentFolderPath,
    this.bottomPadding = 0.0,
  });

  @override
  ConsumerState<FileClipboardBar> createState() => _FileClipboardBarState();
}

class _FileClipboardBarState extends ConsumerState<FileClipboardBar> {
  bool _isPasting = false;

  Future<void> _handlePaste() async {
    final clipboard = ref.read(fileClipboardProvider);
    if (clipboard.isEmpty || _isPasting) return;

    // Resolve target folder path and name
    String? targetPath = widget.currentFolderPath;
    String targetName = widget.currentFolderName ?? 'Folder';

    if (targetPath == null || targetPath.isEmpty) {
      // Try to resolve from foldersProvider
      final foldersAsync = ref.read(foldersProvider);
      final folders = foldersAsync.value ?? [];
      for (final f in folders) {
        if (f.name == widget.currentFolderName) {
          targetPath = f.path;
          targetName = f.name;
          break;
        }
      }
    }

    // Try to resolve from first video in folder if still null
    if ((targetPath == null || targetPath.isEmpty) && widget.currentFolderName != null && widget.currentFolderName != 'root') {
      final videos = ref.read(folderVideosProvider(widget.currentFolderName!).select((s) => s.videos));
      if (videos.isNotEmpty) {
        try {
          targetPath = File(videos.first.path).parent.path;
          targetName = widget.currentFolderName!;
        } catch (_) {}
      }
    }

    if (targetPath == null || targetPath.isEmpty || widget.currentFolderName == 'root') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please open a folder to paste into.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // If moving, check if source and destination are the same
    if (clipboard.isMove && clipboard.items.length == 1 && clipboard.items.first.sourceFolderName == targetName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File is already in this folder.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isPasting = true);

    try {
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

      if (!mounted) return;

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
    } finally {
      if (mounted) {
        setState(() => _isPasting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clipboard = ref.watch(fileClipboardProvider);
    if (clipboard.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final canPaste = widget.currentFolderName != null && widget.currentFolderName != 'root';

    final opLabel = clipboard.isMove ? 'Move' : 'Copy';
    final countLabel = '${clipboard.count} video${clipboard.count > 1 ? 's' : ''}';

    return SafeArea(
      top: false,
      bottom: widget.bottomPadding == 0.0,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark ? const Color(0xFF161616) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.4 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                clipboard.isMove ? Icons.content_cut_rounded : Icons.content_copy_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$opLabel $countLabel',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canPaste ? 'Paste into "${widget.currentFolderName}"' : 'Open a folder to paste',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                size: 20,
              ),
              onPressed: () {
                ref.read(fileClipboardProvider.notifier).clear();
              },
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: canPaste ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                foregroundColor: canPaste
                    ? (theme.brightness == Brightness.dark ? Colors.black : Colors.white)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 0,
              ),
              icon: _isPasting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                      ),
                    )
                  : const Icon(Icons.content_paste_rounded, size: 16),
              label: Text(
                _isPasting ? 'Pasting...' : 'Paste Here',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: (canPaste && !_isPasting) ? _handlePaste : null,
            ),
          ],
        ),
      ),
    ),
  );
}
}
