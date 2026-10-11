import 'dart:io';
import 'package:flutter/material.dart';

class VeilCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String duration;
  final double? progress; // 0.0 to 1.0 (for Continue Watching)
  final String? imagePath; // Local path or asset path
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double aspectRatio;
  final bool isFolder;
  final String? resolution; // e.g. "1080p", "4K"
  final String? size;       // e.g. "1.4 GB"
  final bool isWatched;
  final bool isLastWatched;

  const VeilCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.duration,
    this.progress,
    this.imagePath,
    required this.onTap,
    this.onLongPress,
    this.aspectRatio = 16 / 9,
    this.isFolder = false,
    this.resolution,
    this.size,
    this.isWatched = true,
    this.isLastWatched = false,
  });

  @override
  State<VeilCard> createState() => _VeilCardState();
}

class _VeilCardState extends State<VeilCard> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Metadata details string builder
    final List<String> metadataParts = [];
    if (widget.resolution != null) metadataParts.add(widget.resolution!);
    if (widget.size != null) metadataParts.add(widget.size!);
    final String metadataText = metadataParts.isNotEmpty 
        ? metadataParts.join(' • ') 
        : (widget.subtitle ?? '');
    final String accessibilityLabel = widget.isFolder
        ? 'Folder: ${widget.title}'
        : 'Video: ${widget.title}, duration: ${widget.duration}';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, child) {
        return Transform.translate(
          offset: Offset(0, 8 * (1.0 - animValue)),
          child: Opacity(
            opacity: animValue,
            child: child,
          ),
        );
      },
      child: Semantics(
        button: true,
        label: accessibilityLabel,
        child: GestureDetector(
          onTapDown: (_) => _animController.forward(),
          onTapUp: (_) => _animController.reverse(),
          onTapCancel: () => _animController.reverse(),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: RepaintBoundary(
            child: ScaleTransition(
              scale: _scaleAnimation,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.isLastWatched
                            ? theme.colorScheme.primary.withValues(alpha: 0.6)
                            : (theme.brightness == Brightness.dark ? const Color(0xFF181818) : const Color(0xFFE5E7EB)),
                        width: widget.isLastWatched ? 1.5 : 1.0,
                      ),
                      boxShadow: widget.isLastWatched
                          ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.15), blurRadius: 8, spreadRadius: 1)]
                          : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Thumbnail
                        if (widget.imagePath != null)
                          widget.imagePath!.startsWith('assets/')
                              ? Image.asset(
                                  widget.imagePath!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                                )
                              : Image.file(
                                  File(widget.imagePath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                                )
                        else
                          _buildPlaceholder(),

                        // Folder icon overlay
                        // "Last Played" badge
                        if (widget.isLastWatched && !widget.isFolder)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'LAST PLAYED',
                                    style: TextStyle(
                                      color: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Folder icon overlay
                        if (widget.isFolder)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.folder,
                                color: Colors.amber,
                                size: 14,
                              ),
                            ),
                          ),

                        // "New" badge
                        if (!widget.isWatched && !widget.isLastWatched)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Duration overlay
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.duration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                        // Progress indicator
                        if (widget.progress != null)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: FractionallySizedBox(
                              alignment: Alignment.bottomLeft,
                              widthFactor: widget.progress!.clamp(0.0, 1.0),
                              child: Container(
                                height: 2.5,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: widget.isLastWatched ? FontWeight.bold : FontWeight.w500,
                    color: widget.isLastWatched ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                  ),
                ),
                if (metadataText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    metadataText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildPlaceholder() {
    final theme = Theme.of(context);
    return Container(
      color: theme.brightness == Brightness.dark ? const Color(0xFF070707) : const Color(0xFFF3F4F6),
      alignment: Alignment.center,
      child: Icon(
        widget.isFolder ? Icons.folder_open_rounded : Icons.movie_outlined,
        color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.black12,
        size: widget.aspectRatio < 1.0 ? 32 : 40,
      ),
    );
  }
}
