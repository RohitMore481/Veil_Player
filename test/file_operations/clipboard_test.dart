import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/features/library/models/video_item.dart';
import 'package:veil_player/features/file_operations/providers/file_clipboard_provider.dart';
import 'package:veil_player/features/file_operations/providers/pending_operation_provider.dart';

void main() {
  group('FileClipboardNotifier Tests', () {
    final video1 = VideoItem(
      id: '1',
      title: 'Movie_Part1.mp4',
      path: '/storage/emulated/0/Download/Movie_Part1.mp4',
      duration: const Duration(minutes: 2),
      size: 104857600,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(1600000000000),
      folderName: 'Download',
    );

    final video2 = VideoItem(
      id: '2',
      title: 'Movie_Part2.mp4',
      path: '/storage/emulated/0/Download/Movie_Part2.mp4',
      duration: const Duration(minutes: 3),
      size: 104857600,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(1600000001000),
      folderName: 'Download',
    );

    test('Initial state is empty', () {
      final notifier = FileClipboardNotifier();
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.isNotEmpty, isFalse);
      expect(notifier.state.count, equals(0));
      expect(notifier.state.items, isEmpty);
    });

    test('copySingle sets copy operation with one item', () {
      final notifier = FileClipboardNotifier();
      notifier.copySingle(video1, 'Download');

      expect(notifier.state.isEmpty, isFalse);
      expect(notifier.state.isNotEmpty, isTrue);
      expect(notifier.state.count, equals(1));
      expect(notifier.state.isCopy, isTrue);
      expect(notifier.state.isMove, isFalse);
      expect(notifier.state.items.first.id, equals('1'));
      expect(notifier.state.items.first.title, equals('Movie_Part1.mp4'));
      expect(notifier.state.items.first.path, equals('/storage/emulated/0/Download/Movie_Part1.mp4'));
      expect(notifier.state.items.first.sourceFolderName, equals('Download'));
      expect(notifier.state.paths, equals(['/storage/emulated/0/Download/Movie_Part1.mp4']));
      expect(notifier.state.ids, equals(['1']));
    });

    test('moveSingle sets move operation with one item', () {
      final notifier = FileClipboardNotifier();
      notifier.moveSingle(video1, 'Download');

      expect(notifier.state.count, equals(1));
      expect(notifier.state.isMove, isTrue);
      expect(notifier.state.isCopy, isFalse);
      expect(notifier.state.items.first.id, equals('1'));
      expect(notifier.state.items.first.sourceFolderName, equals('Download'));
    });

    test('copyBatch sets copy operation with multiple items', () {
      final notifier = FileClipboardNotifier();
      notifier.copyBatch([video1, video2], 'Download');

      expect(notifier.state.count, equals(2));
      expect(notifier.state.isCopy, isTrue);
      expect(notifier.state.ids, equals(['1', '2']));
      expect(notifier.state.paths, equals([
        '/storage/emulated/0/Download/Movie_Part1.mp4',
        '/storage/emulated/0/Download/Movie_Part2.mp4',
      ]));
      expect(notifier.state.sourceFolderNames, equals({'Download'}));
    });

    test('moveBatch sets move operation with multiple items', () {
      final notifier = FileClipboardNotifier();
      notifier.moveBatch([video1, video2], 'Download');

      expect(notifier.state.count, equals(2));
      expect(notifier.state.isMove, isTrue);
      expect(notifier.state.ids, equals(['1', '2']));
      expect(notifier.state.paths.length, equals(2));
    });

    test('clear resets state back to empty', () {
      final notifier = FileClipboardNotifier();
      notifier.copyBatch([video1, video2], 'Download');
      expect(notifier.state.isNotEmpty, isTrue);

      notifier.clear();
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.count, equals(0));
      expect(notifier.state.items, isEmpty);
    });
  });

  group('File Operations Models Tests', () {
    test('CopyVideoOp properties', () {
      final op = CopyVideoOp(
        id: '1',
        path: '/storage/emulated/0/Download/clip.mp4',
        targetFolder: '/storage/emulated/0/Movies',
        targetFolderName: 'Movies',
        sourceFolderName: 'Download',
      );

      expect(op.id, '1');
      expect(op.path, '/storage/emulated/0/Download/clip.mp4');
      expect(op.targetFolder, '/storage/emulated/0/Movies');
      expect(op.targetFolderName, 'Movies');
      expect(op.sourceFolderName, 'Download');
    });

    test('MoveVideoOp properties', () {
      final op = MoveVideoOp(
        id: '1',
        path: '/storage/emulated/0/Download/clip.mp4',
        targetFolder: '/storage/emulated/0/Movies',
        targetFolderName: 'Movies',
        sourceFolderName: 'Download',
      );

      expect(op.id, '1');
      expect(op.path, '/storage/emulated/0/Download/clip.mp4');
      expect(op.targetFolder, '/storage/emulated/0/Movies');
      expect(op.targetFolderName, 'Movies');
      expect(op.sourceFolderName, 'Download');
    });

    test('BatchCopyVideoOp properties', () {
      final op = BatchCopyVideoOp(
        paths: ['/a/1.mp4', '/a/2.mp4'],
        targetFolder: '/b',
        targetFolderName: 'b',
        sourceFolderNames: {'a'},
      );

      expect(op.paths.length, 2);
      expect(op.targetFolder, '/b');
    });

    test('BatchMoveVideoOp properties', () {
      final op = BatchMoveVideoOp(
        ids: ['1', '2'],
        paths: ['/a/1.mp4', '/a/2.mp4'],
        targetFolder: '/b',
        targetFolderName: 'b',
        sourceFolderNames: {'a'},
      );

      expect(op.ids.length, 2);
      expect(op.paths.length, 2);
      expect(op.targetFolder, '/b');
    });
  });
}
