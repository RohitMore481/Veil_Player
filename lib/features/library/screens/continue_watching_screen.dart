import 'package:flutter/material.dart';
import '../../../core/widgets/veil_card.dart';
import '../../../core/widgets/veil_button.dart';
import '../../player/screens/player_screen.dart';
import '../../../core/utils/page_transitions.dart';

class ContinueWatchingScreen extends StatefulWidget {
  const ContinueWatchingScreen({super.key});

  @override
  State<ContinueWatchingScreen> createState() => _ContinueWatchingScreenState();
}

class _ContinueWatchingScreenState extends State<ContinueWatchingScreen> {
  // Mock data for Continue Watching items
  final List<_ResumeItem> _resumeItems = [
    _ResumeItem(
      title: 'Oppenheimer (2023)',
      subtitle: '3.1 GB • Ultra HD',
      duration: '3:00:21',
      lastWatched: '1:57:13 left',
      progress: 0.65,
    ),
    _ResumeItem(
      title: 'Succession S04E10',
      subtitle: '1.2 GB • 1080p',
      duration: '1:18:45',
      lastWatched: '1:09:12 left',
      progress: 0.12,
    ),
    _ResumeItem(
      title: 'Dune: Part Two (2024)',
      subtitle: '4.8 GB • 4K HDR',
      duration: '2:46:10',
      lastWatched: '16:37 left',
      progress: 0.90,
    ),
    _ResumeItem(
      title: 'The Bear S02E06 - Fishes',
      subtitle: '800 MB • 1080p',
      duration: '1:06:05',
      lastWatched: '33:02 left',
      progress: 0.50,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final crossAxisCount = isLandscape ? 3 : 2;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: VeilButton(
          type: VeilButtonType.icon,
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.pop(context),
        ),
        title: Text(
          'Continue Watching',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all_rounded, color: Colors.white60),
            onPressed: () {
              setState(() {
                _resumeItems.clear();
              });
            },
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: _resumeItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Colors.white24,
                    size: 72,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No resume history',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.textTheme.labelMedium?.color,
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: _resumeItems.length,
              itemBuilder: (context, index) {
                final item = _resumeItems[index];

                return Dismissible(
                  key: Key(item.title),
                  direction:
                      DismissDirection.vertical, // swipe vertically to remove
                  onDismissed: (_) {
                    setState(() {
                      _resumeItems.removeAt(index);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed "${item.title}" progress'),
                        backgroundColor: const Color(0xFF111111),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  background: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                  ),
                  child: VeilCard(
                    title: item.title,
                    subtitle: '${item.subtitle} • ${item.lastWatched}',
                    duration: item.duration,
                    progress: item.progress,
                    onTap: () {
                      Navigator.push(
                        context,
                        VeilPageRoute(builder: (_) => const PlayerScreen()),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _ResumeItem {
  final String title;
  final String subtitle;
  final String duration;
  final String lastWatched;
  final double progress;

  const _ResumeItem({
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.lastWatched,
    required this.progress,
  });
}
