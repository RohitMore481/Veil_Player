import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/repositories/media_repository.dart';
import '../../library/providers/media_provider.dart';
import '../services/file_operation_service.dart';
import '../../player/providers/active_video_provider.dart';

final pendingOperationManagerProvider = Provider((ref) {
  return PendingOperationManager(ref);
});

sealed class PendingOperation {}

class DeleteVideoOp extends PendingOperation {
  final String id;
  final String path;
  final String folderName;

  DeleteVideoOp({required this.id, required this.path, required this.folderName});
}

class RenameVideoOp extends PendingOperation {
  final String id;
  final String path;
  final String newName;
  final String folderName;

  RenameVideoOp({required this.id, required this.path, required this.newName, required this.folderName});
}

class DeleteFolderOp extends PendingOperation {
  final String path;

  DeleteFolderOp({required this.path});
}

class RenameFolderOp extends PendingOperation {
  final String path;
  final String newName;

  RenameFolderOp({required this.path, required this.newName});
}

class BatchDeleteVideoOp extends PendingOperation {
  final List<String> ids;
  final List<String> paths;
  final Set<String> folderNames;

  BatchDeleteVideoOp({required this.ids, required this.paths, required this.folderNames});
}

class CopyVideoOp extends PendingOperation {
  final String id;
  final String path;
  final String targetFolder;
  final String targetFolderName;
  final String sourceFolderName;

  CopyVideoOp({
    required this.id,
    required this.path,
    required this.targetFolder,
    required this.targetFolderName,
    required this.sourceFolderName,
  });
}

class MoveVideoOp extends PendingOperation {
  final String id;
  final String path;
  final String targetFolder;
  final String targetFolderName;
  final String sourceFolderName;

  MoveVideoOp({
    required this.id,
    required this.path,
    required this.targetFolder,
    required this.targetFolderName,
    required this.sourceFolderName,
  });
}

class BatchCopyVideoOp extends PendingOperation {
  final List<String> paths;
  final String targetFolder;
  final String targetFolderName;
  final Set<String> sourceFolderNames;

  BatchCopyVideoOp({
    required this.paths,
    required this.targetFolder,
    required this.targetFolderName,
    required this.sourceFolderNames,
  });
}

class BatchMoveVideoOp extends PendingOperation {
  final List<String> ids;
  final List<String> paths;
  final String targetFolder;
  final String targetFolderName;
  final Set<String> sourceFolderNames;

  BatchMoveVideoOp({
    required this.ids,
    required this.paths,
    required this.targetFolder,
    required this.targetFolderName,
    required this.sourceFolderNames,
  });
}

class PendingOperationManager {
  final Ref _ref;

  PendingOperationManager(this._ref);

  MediaRepository get _repo => _ref.read(mediaRepositoryProvider);

  /// Executes an operation. If SAF permission is required, it automatically requests it,
  /// waits for the user to grant it, and immediately retries the operation.
  /// 
  /// Returns a tuple of (success: bool, message: String).
  Future<(bool, String)> execute(PendingOperation op) async {
    // Check if the operation affects the currently playing video
    final activeVideo = _ref.read(activeVideoProvider);
    bool isPlayingActive = false;

    if (op is DeleteVideoOp && activeVideo?.id == op.id) {
      isPlayingActive = true;
    } else if (op is RenameVideoOp && activeVideo?.id == op.id) {
      isPlayingActive = true;
    } else if (op is MoveVideoOp && activeVideo?.id == op.id) {
      isPlayingActive = true;
    } else if (op is BatchDeleteVideoOp && activeVideo != null && op.ids.contains(activeVideo.id)) {
      isPlayingActive = true;
    } else if (op is BatchMoveVideoOp && activeVideo != null && op.ids.contains(activeVideo.id)) {
      isPlayingActive = true;
    }

    if (isPlayingActive) {
      // Clear active video first to trigger PlayerScreen auto-pop
      _ref.read(activeVideoProvider.notifier).state = null;
      // Allow a brief moment for the UI transition before writing to disk
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // 1. Initial Attempt
    FileOpResult result = await _runOp(op);

    // 2. Handle SAF Permission
    if (result == FileOpResult.safPermissionRequired) {
      final safPath = _getSafPathForOp(op);
      final granted = await _repo.requestSafPermission(safPath);
      
      if (granted) {
        // Automatically retry after permission granted
        result = await _runOp(op);
      } else {
        return (false, 'Storage permission denied.');
      }
    }

    // 3. Handle Result
    if (result == FileOpResult.success) {
      await _invalidateProvidersForOp(op);
      return (true, _getSuccessMessage(op));
    } else if (result == FileOpResult.cancelled) {
      return (false, ''); // Silently fail on cancel
    } else {
      return (false, 'An error occurred during the operation.');
    }
  }

  Future<FileOpResult> _runOp(PendingOperation op) async {
    if (op is DeleteVideoOp) {
      return await _repo.deleteVideo(op.id, op.path);
    } else if (op is RenameVideoOp) {
      return await _repo.renameVideo(op.id, op.path, op.newName);
    } else if (op is DeleteFolderOp) {
      return await _repo.deleteFolder(op.path);
    } else if (op is RenameFolderOp) {
      return await _repo.renameFolder(op.path, op.newName);
    } else if (op is BatchDeleteVideoOp) {
      return await _repo.deleteVideosBatch(op.ids, op.paths);
    } else if (op is CopyVideoOp) {
      return await _repo.copyVideo(op.path, op.targetFolder);
    } else if (op is MoveVideoOp) {
      return await _repo.moveVideo(op.id, op.path, op.targetFolder);
    } else if (op is BatchCopyVideoOp) {
      return await _repo.copyVideosBatch(op.paths, op.targetFolder);
    } else if (op is BatchMoveVideoOp) {
      return await _repo.moveVideosBatch(op.ids, op.paths, op.targetFolder);
    }
    return FileOpResult.error;
  }

  String _getSafPathForOp(PendingOperation op) {
    if (op is DeleteVideoOp) return Directory(op.path).parent.path;
    if (op is RenameVideoOp) return Directory(op.path).parent.path;
    if (op is DeleteFolderOp) return op.path;
    if (op is RenameFolderOp) return op.path;
    if (op is BatchDeleteVideoOp) {
      if (op.paths.isNotEmpty) return Directory(op.paths.first).parent.path;
      return '';
    }
    if (op is CopyVideoOp) return op.targetFolder;
    if (op is MoveVideoOp) return op.targetFolder;
    if (op is BatchCopyVideoOp) return op.targetFolder;
    if (op is BatchMoveVideoOp) return op.targetFolder;
    return '';
  }

  Future<void> _invalidateProvidersForOp(PendingOperation op) async {
    _ref.invalidate(foldersProvider);
    _ref.invalidate(playbackHistoryProvider);
    _ref.invalidate(searchResultsProvider);
    
    if (op is DeleteVideoOp) {
      await _ref.read(playbackHistoryProvider.notifier).clearHistoryItem(op.id);
      _ref.read(folderVideosProvider(op.folderName).notifier).refresh();
    } else if (op is RenameVideoOp) {
      _ref.read(folderVideosProvider(op.folderName).notifier).refresh();
    } else if (op is DeleteFolderOp) {
      final isPinned = _ref.read(pinnedFoldersProvider.notifier).isPinned(op.path);
      if (isPinned) {
        await _ref.read(pinnedFoldersProvider.notifier).togglePin(op.path);
      }
    } else if (op is RenameFolderOp) {
      final isPinned = _ref.read(pinnedFoldersProvider.notifier).isPinned(op.path);
      if (isPinned) {
        final parent = Directory(op.path).parent.path;
        final newPath = '$parent/${op.newName}';
        await _ref.read(pinnedFoldersProvider.notifier).updatePinnedFolder(op.path, newPath);
      }
    } else if (op is BatchDeleteVideoOp) {
      for (final id in op.ids) {
        await _ref.read(playbackHistoryProvider.notifier).clearHistoryItem(id);
      }
      for (final folderName in op.folderNames) {
        _ref.read(folderVideosProvider(folderName).notifier).refresh();
      }
    } else if (op is CopyVideoOp) {
      _ref.read(folderVideosProvider(op.targetFolderName).notifier).refresh();
      if (op.sourceFolderName != op.targetFolderName) {
        _ref.read(folderVideosProvider(op.sourceFolderName).notifier).refresh();
      }
    } else if (op is MoveVideoOp) {
      _ref.read(folderVideosProvider(op.targetFolderName).notifier).refresh();
      if (op.sourceFolderName != op.targetFolderName) {
        _ref.read(folderVideosProvider(op.sourceFolderName).notifier).refresh();
      }
    } else if (op is BatchCopyVideoOp) {
      _ref.read(folderVideosProvider(op.targetFolderName).notifier).refresh();
      for (final folderName in op.sourceFolderNames) {
        if (folderName != op.targetFolderName) {
          _ref.read(folderVideosProvider(folderName).notifier).refresh();
        }
      }
    } else if (op is BatchMoveVideoOp) {
      _ref.read(folderVideosProvider(op.targetFolderName).notifier).refresh();
      for (final folderName in op.sourceFolderNames) {
        if (folderName != op.targetFolderName) {
          _ref.read(folderVideosProvider(folderName).notifier).refresh();
        }
      }
    }
  }

  String _getSuccessMessage(PendingOperation op) {
    if (op is DeleteVideoOp) return 'Video deleted';
    if (op is RenameVideoOp) return 'Video renamed to ${op.newName}';
    if (op is DeleteFolderOp) return 'Folder deleted';
    if (op is RenameFolderOp) return 'Folder renamed to ${op.newName}';
    if (op is BatchDeleteVideoOp) return '${op.ids.length} videos deleted';
    if (op is CopyVideoOp) return 'Video copied to ${op.targetFolderName}';
    if (op is MoveVideoOp) return 'Video moved to ${op.targetFolderName}';
    if (op is BatchCopyVideoOp) return '${op.paths.length} videos copied to ${op.targetFolderName}';
    if (op is BatchMoveVideoOp) return '${op.ids.length} videos moved to ${op.targetFolderName}';
    return 'Operation successful';
  }
}
