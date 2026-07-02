import 'package:flutter/material.dart';

class VeilSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const VeilSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  State<VeilSlider> createState() => _VeilSliderState();
}

class _VeilSliderState extends State<VeilSlider>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _trackHeightAnimation;
  late Animation<double> _thumbSizeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _trackHeightAnimation = Tween<double>(
      begin: 3.0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _thumbSizeAnimation = Tween<double>(
      begin: 0.0,
      end: 12.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details, double width) {
    _animController.forward();
    final double percentage = (details.localPosition.dx / width).clamp(
      0.0,
      1.0,
    );
    final double value = widget.min + percentage * (widget.max - widget.min);
    widget.onChangeStart?.call(value);
    widget.onChanged(value);
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    final double percentage = (details.localPosition.dx / width).clamp(
      0.0,
      1.0,
    );
    final double value = widget.min + percentage * (widget.max - widget.min);
    widget.onChanged(value);
  }

  void _handleDragEnd(DragEndDetails details) {
    _animController.reverse();
    widget.onChangeEnd?.call(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double percent = widget.max > widget.min
            ? ((widget.value - widget.min) / (widget.max - widget.min)).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) => _handleDragStart(details, width),
          onHorizontalDragUpdate: (details) =>
              _handleDragUpdate(details, width),
          onHorizontalDragEnd: _handleDragEnd,
          onTapDown: (details) {
            _handleDragStart(
              DragStartDetails(localPosition: details.localPosition),
              width,
            );
            _handleDragEnd(DragEndDetails());
          },
          child: Container(
            height: 24, // Touch target
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final double trackHeight = _trackHeightAnimation.value;
                final double thumbSize = _thumbSizeAnimation.value;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Inactive track
                    Container(
                      height: trackHeight,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            theme.sliderTheme.inactiveTrackColor ??
                            (theme.brightness == Brightness.dark
                                ? Colors.white10
                                : Colors.black12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Active track
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: percent,
                      child: Container(
                        height: trackHeight,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Thumb
                    if (thumbSize > 0.0)
                      Positioned(
                        left: (percent * width) - (thumbSize / 2),
                        top: (trackHeight / 2) - (thumbSize / 2),
                        child: Container(
                          width: thumbSize,
                          height: thumbSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
