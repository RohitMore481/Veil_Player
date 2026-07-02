import 'package:flutter/material.dart';

class DoubleTapRipple extends StatefulWidget {
  final bool isLeft;
  final VoidCallback onCompleted;

  const DoubleTapRipple({
    super.key,
    required this.isLeft,
    required this.onCompleted,
  });

  @override
  State<DoubleTapRipple> createState() => _DoubleTapRippleState();
}

class _DoubleTapRippleState extends State<DoubleTapRipple>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 0.4), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 0.4, end: 0.4), weight: 40),
      TweenSequenceItem(tween: Tween<double>(begin: 0.4, end: 0.0), weight: 30),
    ]).animate(_controller);

    _scale = Tween<double>(
      begin: 0.8,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward().then((_) {
      if (mounted) {
        widget.onCompleted();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Alignment alignment = widget.isLeft
        ? Alignment.centerLeft
        : Alignment.centerRight;
    final BorderRadius borderRadius = widget.isLeft
        ? const BorderRadius.horizontal(right: Radius.circular(300))
        : const BorderRadius.horizontal(left: Radius.circular(300));

    return Align(
      alignment: alignment,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.35,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: borderRadius,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.isLeft
                        ? Icons.fast_rewind_rounded
                        : Icons.fast_forward_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.isLeft ? '-10s' : '+10s',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
