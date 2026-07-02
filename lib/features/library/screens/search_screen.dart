import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/veil_card.dart';
import '../../../core/widgets/veil_button.dart';
import '../../player/screens/player_screen.dart';
import '../../../core/utils/page_transitions.dart';
import '../providers/media_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        ref.read(searchQueryProvider.notifier).state = text;
      }
    });
  }

  void _clearSearch() {
    _textController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final crossAxisCount = isLandscape ? 4 : 2;

    final query = ref.watch(searchQueryProvider);
    final searchResultAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  VeilButton(
                    type: VeilButtonType.icon,
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF0F0F0F)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFF1E1E1E)
                              : const Color(0xFFE5E7EB),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              onChanged: _onSearchChanged,
                              cursorColor: theme.colorScheme.primary,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search videos, folders...',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.3,
                                  ),
                                  fontSize: 15,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_textController.text.isNotEmpty)
                            GestureDetector(
                              onTap: _clearSearch,
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            Divider(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF131313)
                  : const Color(0xFFE5E7EB),
              height: 1,
            ),

            // Search Results area
            Expanded(
              child: query.isEmpty
                  ? _buildEmptyState(theme, 'Type to search local library')
                  : searchResultAsync.when(
                      data: (videos) {
                        if (videos.isEmpty) {
                          return _buildEmptyState(
                            theme,
                            'No videos found for "$query"',
                          );
                        }

                        return CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.only(
                                left: 16.0,
                                right: 16.0,
                                top: 16.0,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 10,
                                      childAspectRatio: 1.15,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final video = videos[index];
                                  return Consumer(
                                    builder: (context, ref, child) {
                                      final thumbnailAsync = ref.watch(
                                        videoThumbnailProvider(video),
                                      );
                                      return VeilCard(
                                        title: video.title,
                                        duration: video.formattedDuration,
                                        size: video.formattedSize,
                                        imagePath: thumbnailAsync.value,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            VeilPageRoute(
                                              builder: (_) =>
                                                  PlayerScreen(video: video),
                                            ),
                                          ).then((_) {
                                            ref.invalidate(
                                              playbackHistoryProvider,
                                            );
                                          });
                                        },
                                      );
                                    },
                                  );
                                }, childCount: videos.length),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 24),
                            ),
                          ],
                        );
                      },
                      loading: () => Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                          strokeWidth: 2,
                        ),
                      ),
                      error: (err, stack) => Center(
                        child: Text(
                          'Error performing search: $err',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.38,
                            ),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              size: 72,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
