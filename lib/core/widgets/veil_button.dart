import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/veil_theme.dart';

enum VeilButtonType { primary, secondary, text, icon }

class VeilButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget? child;
  final IconData? icon;
  final String? label;
  final VeilButtonType type;
  final bool isDisabled;
  final double? width;
  final double height;
  final double iconSize;
  final BoxShape shape;
  final Color? iconColor;

  const VeilButton({
    super.key,
    required this.onTap,
    this.child,
    this.icon,
    this.label,
    this.type = VeilButtonType.primary,
    this.isDisabled = false,
    this.width,
    this.height = 48,
    this.iconSize = 20,
    this.shape = BoxShape.rectangle,
    this.iconColor,
  }) : assert(
         child != null || label != null || icon != null,
         'Must provide child, label, or icon',
       );

  @override
  State<VeilButton> createState() => _VeilButtonState();
}

class _VeilButtonState extends State<VeilButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: VeilMotion.fast,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: VeilMotion.scaleButton)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: VeilMotion.curveSharp,
          ),
        );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.isDisabled && widget.onTap != null) {
      _animationController.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.isDisabled && widget.onTap != null) {
      _animationController.reverse();
    }
  }

  void _handleTapCancel() {
    if (!widget.isDisabled && widget.onTap != null) {
      _animationController.reverse();
    }
  }

  void _triggerTap() {
    if (!widget.isDisabled && widget.onTap != null) {
      HapticFeedback.lightImpact();
      widget.onTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;

    Widget buttonContent;
    if (widget.child != null) {
      buttonContent = widget.child!;
    } else {
      final children = <Widget>[];
      if (widget.icon != null) {
        children.add(
          Icon(
            widget.icon,
            size: widget.iconSize,
            color:
                widget.iconColor ??
                (widget.type == VeilButtonType.primary
                    ? Colors.black
                    : theme.colorScheme.onSurface),
          ),
        );
      }
      if (widget.label != null) {
        if (children.isNotEmpty) children.add(const SizedBox(width: 8));
        children.add(
          Text(
            widget.label!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: widget.type == VeilButtonType.primary
                  ? Colors.black
                  : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }
      buttonContent = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    BoxDecoration decoration;
    EdgeInsets padding = widget.shape == BoxShape.circle
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 16);

    switch (widget.type) {
      case VeilButtonType.primary:
        decoration = BoxDecoration(
          color: widget.isDisabled ? theme.disabledColor : accentColor,
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.circle
              ? null
              : BorderRadius.circular(12),
        );
        break;
      case VeilButtonType.secondary:
        decoration = BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF111111)
              : const Color(0xFFF3F4F6),
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.circle
              ? null
              : BorderRadius.circular(12),
          border: widget.shape == BoxShape.circle
              ? null
              : Border.all(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFE5E7EB),
                  width: 1,
                ),
        );
        break;
      case VeilButtonType.text:
        decoration = const BoxDecoration();
        padding = EdgeInsets.zero;
        break;
      case VeilButtonType.icon:
        decoration = const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        );
        padding = EdgeInsets.zero;
        break;
    }

    if (widget.type == VeilButtonType.icon) {
      return Semantics(
        button: true,
        enabled: !widget.isDisabled,
        label: widget.label ?? 'button',
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: widget.isDisabled ? null : _triggerTap,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: widget.width ?? widget.height,
              height: widget.height,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.isDisabled
                    ? theme.disabledColor
                    : (widget.iconColor ?? theme.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: !widget.isDisabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.isDisabled ? null : _triggerTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: widget.width,
            height: widget.height,
            padding: padding,
            alignment: Alignment.center,
            decoration: decoration,
            child: buttonContent,
          ),
        ),
      ),
    );
  }
}
