import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../providers/playlists_provider.dart';

class CreatePlaylistDialog extends ConsumerStatefulWidget {
  final Playlist? initialPlaylist; // If provided, acts as Rename dialog

  const CreatePlaylistDialog({super.key, this.initialPlaylist});

  @override
  ConsumerState<CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<CreatePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialPlaylist?.name ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final isEditing = widget.initialPlaylist != null;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF16181D) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        isEditing ? 'Rename Playlist' : 'New Playlist',
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: isDark ? Colors.white24 : const Color(0xFFD1D5DB),
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: primary, width: 2),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          onPressed: _submit,
          child: Text(
            isEditing ? 'Save' : 'Create',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  void _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    if (widget.initialPlaylist != null) {
      await ref
          .read(playlistsProvider.notifier)
          .renamePlaylist(widget.initialPlaylist!.id, name);
      if (mounted) Navigator.pop(context);
    } else {
      final created =
          await ref.read(playlistsProvider.notifier).createPlaylist(name);
      if (mounted) Navigator.pop(context, created);
    }
  }
}
