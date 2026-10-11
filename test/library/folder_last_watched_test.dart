import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/features/library/models/video_item.dart';

void main() {
  group('FolderItem.findLastWatchedFolder Tests', () {
    const dcim = FolderItem(
      name: 'DCIM',
      path: '/storage/emulated/0/DCIM',
      count: 5,
      containsMovies: false,
    );
    const camera = FolderItem(
      name: 'Camera',
      path: '/storage/emulated/0/DCIM/Camera',
      count: 12,
      containsMovies: false,
    );
    const movies = FolderItem(
      name: 'Movies',
      path: '/storage/emulated/0/Movies',
      count: 8,
      containsMovies: true,
    );
    const actionMovies = FolderItem(
      name: 'Action',
      path: '/storage/emulated/0/Movies/Action',
      count: 3,
      containsMovies: true,
    );
    const download = FolderItem(
      name: 'Download',
      path: '/storage/emulated/0/Download',
      count: 20,
      containsMovies: false,
    );

    final allFolders = [dcim, camera, movies, actionMovies, download];

    test('Picks exact subfolder (Camera) over parent folder (DCIM)', () {
      const videoPath = '/storage/emulated/0/DCIM/Camera/VID_20261011_001.mp4';
      final match = FolderItem.findLastWatchedFolder(allFolders, videoPath);

      expect(match, equals(camera));
      expect(match, isNot(equals(dcim)));

      // Verify that testing every folder in the list results in exactly 1 highlighted folder
      final highlighted = allFolders.where((f) => f == match).toList();
      expect(highlighted.length, 1);
      expect(highlighted.first.name, 'Camera');
    });

    test('Picks parent folder (DCIM) when video is directly in DCIM and not in Camera', () {
      const videoPath = '/storage/emulated/0/DCIM/preview.mp4';
      final match = FolderItem.findLastWatchedFolder(allFolders, videoPath);

      expect(match, equals(dcim));
      expect(match, isNot(equals(camera)));

      final highlighted = allFolders.where((f) => f == match).toList();
      expect(highlighted.length, 1);
      expect(highlighted.first.name, 'DCIM');
    });

    test('Picks exact subfolder (Action) over parent (Movies)', () {
      const videoPath = '/storage/emulated/0/Movies/Action/MissionImpossible.mkv';
      final match = FolderItem.findLastWatchedFolder(allFolders, videoPath);

      expect(match, equals(actionMovies));
      expect(match, isNot(equals(movies)));

      final highlighted = allFolders.where((f) => f == match).toList();
      expect(highlighted.length, 1);
    });

    test('Picks deepest ancestor when direct subfolder is not in list', () {
      // Suppose the video is in a subfolder "SciFi" that is not in the folders list
      const videoPath = '/storage/emulated/0/Movies/SciFi/Interstellar.mkv';
      final match = FolderItem.findLastWatchedFolder(allFolders, videoPath);

      expect(match, equals(movies));
      expect(match, isNot(equals(actionMovies)));

      final highlighted = allFolders.where((f) => f == match).toList();
      expect(highlighted.length, 1);
    });

    test('Handles Windows-style backslashes correctly', () {
      const winVideoPath = r'C:\Users\User\Videos\DCIM\Camera\clip.mp4';
      const winDcim = FolderItem(
        name: 'DCIM',
        path: r'C:\Users\User\Videos\DCIM',
        count: 2,
        containsMovies: false,
      );
      const winCamera = FolderItem(
        name: 'Camera',
        path: r'C:\Users\User\Videos\DCIM\Camera',
        count: 5,
        containsMovies: false,
      );

      final folders = [winDcim, winCamera];
      final match = FolderItem.findLastWatchedFolder(folders, winVideoPath);

      expect(match, equals(winCamera));
      expect(match, isNot(equals(winDcim)));
      final highlighted = folders.where((f) => f == match).toList();
      expect(highlighted.length, 1);
    });

    test('Returns null when no folders match', () {
      const videoPath = '/storage/emulated/0/OtherFolder/clip.mp4';
      final match = FolderItem.findLastWatchedFolder(allFolders, videoPath);

      expect(match, isNull);
      final highlighted = allFolders.where((f) => f == match).toList();
      expect(highlighted.isEmpty, isTrue);
    });

    test('Returns null when history is empty or path is null', () {
      expect(FolderItem.findLastWatchedFolder(allFolders, null), isNull);
      expect(FolderItem.findLastWatchedFolder(allFolders, ''), isNull);
      expect(FolderItem.findLastWatchedFolder([], '/storage/emulated/0/DCIM/Camera/VID.mp4'), isNull);
    });
  });
}
