import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../file_operations/services/file_operation_service.dart';
import '../models/audio_item.dart';
import '../providers/audio_library_providers.dart';
import '../providers/audio_player_provider.dart';
import '../providers/playlists_provider.dart';
import '../services/audio_file_operation_service.dart';
import 'add_to_playlist_sheet.dart';
import 'audio_folder_picker_sheet.dart';

class AudioTrackOverflowSheet extends ConsumerWidget {
  final AudioTrackItem track;

  const AudioTrackOverflowSheet({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14171A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Track Info Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.music_note_rounded, color: primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${track.artist} • ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Playback Actions
            ListTile(
              leading: Icon(Icons.play_arrow_rounded, color: primary),
              title: const Text('Play Now'),
              onTap: () {
                Navigator.pop(context);
                ref.read(audioPlayerProvider.notifier).playNow(track);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_play_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Play Next'),
              onTap: () {
                Navigator.pop(context);
                ref.read(audioPlayerProvider.notifier).playNext(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playing next: "${track.title}"'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Add to Queue'),
              onTap: () {
                Navigator.pop(context);
                ref.read(audioPlayerProvider.notifier).addTrack(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added to queue: "${track.title}"'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Add to Playlist'),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => AddToPlaylistSheet(tracks: [track]),
                );
              },
            ),

            const Divider(height: 16),

            // File Management Actions
            ListTile(
              leading: Icon(Icons.edit_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Rename Song'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.drive_file_move_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Move to Folder'),
              onTap: () async {
                Navigator.pop(context);
                final targetFolder = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => AudioFolderPickerSheet(
                    title: 'Move Song to Folder',
                    currentFolderPath: track.folderPath,
                  ),
                );
                if (targetFolder != null && targetFolder.isNotEmpty && context.mounted) {
                  _executeMove(context, ref, targetFolder);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.content_copy_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Copy to Folder'),
              onTap: () async {
                Navigator.pop(context);
                final targetFolder = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => AudioFolderPickerSheet(
                    title: 'Copy Song to Folder',
                    currentFolderPath: track.folderPath,
                  ),
                );
                if (targetFolder != null && targetFolder.isNotEmpty && context.mounted) {
                  _executeCopy(context, ref, targetFolder);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('Delete Song',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(context, ref);
              },
            ),

            const Divider(height: 16),

            // File Details
            ListTile(
              leading: Icon(Icons.info_outline_rounded,
                  color: isDark ? Colors.white70 : Colors.black87),
              title: const Text('Song Details'),
              onTap: () {
                Navigator.pop(context);
                _showDetailsDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = TextEditingController(text: track.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF14171A) : Colors.white,
        title: const Text('Rename Song'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Song Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != track.title) {
                Navigator.pop(ctx);
                final service = AudioFileOperationService();
                final result = await service.renameAudio(track.id, track.path, newName);
                if (result == FileOpResult.success) {
                  ref
                      .read(audioPlayerProvider.notifier)
                      .updateTrackInfo(track.id, newTitle: newName);
                  ref.read(allAudioTracksProvider.notifier).refresh();
                  ref.invalidate(audioFoldersProvider);
                  ref.invalidate(recentlyPlayedAudioProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Renamed to "$newName"')),
                          ],
                        ),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to rename song file.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _executeMove(BuildContext context, WidgetRef ref, String targetFolder) async {
    final service = AudioFileOperationService();
    final result = await service.moveAudio(track.id, track.path, targetFolder);
    if (result == FileOpResult.success) {
      final fileName = track.path.split(RegExp(r'[/\\]')).last;
      final newPath = '$targetFolder/$fileName';
      ref
          .read(audioPlayerProvider.notifier)
          .updateTrackInfo(track.id, newPath: newPath);
      ref.read(allAudioTracksProvider.notifier).refresh();
      ref.invalidate(audioFoldersProvider);
      ref.invalidate(recentlyPlayedAudioProvider);
      if (context.mounted) {
        final folderName = targetFolder.split(RegExp(r'[/\\]')).last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Moved "${track.title}" to $folderName')),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to move song file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _executeCopy(BuildContext context, WidgetRef ref, String targetFolder) async {
    final service = AudioFileOperationService();
    final result = await service.copyAudio(track.path, targetFolder);
    if (result == FileOpResult.success) {
      ref.read(allAudioTracksProvider.notifier).refresh();
      ref.invalidate(audioFoldersProvider);
      if (context.mounted) {
        final folderName = targetFolder.split(RegExp(r'[/\\]')).last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Copied "${track.title}" to $folderName')),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to copy song file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF14171A) : Colors.white,
        title: const Text('Delete Song?'),
        content: Text(
          'Are you sure you want to permanently delete "${track.title}" from your device? This action cannot be undone.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final service = AudioFileOperationService();
              final result = await service.deleteAudio(track.id, track.path);
              if (result == FileOpResult.success) {
                await ref
                    .read(audioPlayerProvider.notifier)
                    .removeTrackById(track.id);
                await ref
                    .read(audioPlayerProvider.notifier)
                    .removeRecentlyPlayedTrack(track.id);
                await ref
                    .read(playlistsProvider.notifier)
                    .removeTrackFromAllPlaylists(track.id);
                ref.read(allAudioTracksProvider.notifier).refresh();
                ref.invalidate(audioFoldersProvider);
                ref.invalidate(recentlyPlayedAudioProvider);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Deleted "${track.title}"')),
                        ],
                      ),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete song file.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(track.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Artist', track.artist),
            _buildDetailRow('Album', track.album),
            _buildDetailRow('Duration', track.formattedDuration),
            _buildDetailRow('Size', track.formattedSize),
            if (track.trackNumber != null)
              _buildDetailRow('Track #', '${track.trackNumber}'),
            _buildDetailRow('Folder', track.folderName),
            _buildDetailRow('Path', track.path),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.grey),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
