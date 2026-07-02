class SubtitleSettings {
  final bool enabled;
  final double fontSize;
  final String textColor; // Hex string e.g. '#FFFFFF'
  final String backgroundColor; // Hex string e.g. '#000000'
  final double verticalPosition; // 0.0 (bottom) to 1.0 (top)
  final double opacity; // Subtitle text opacity (0.0 to 1.0)

  const SubtitleSettings({
    this.enabled = true,
    this.fontSize = 18.0, // Default to Medium (18.0)
    this.textColor = '#FFFFFF',
    this.backgroundColor = '#00000000', // None
    this.verticalPosition = 0.08,
    this.opacity = 1.0,
  });

  SubtitleSettings copyWith({
    bool? enabled,
    double? fontSize,
    String? textColor,
    String? backgroundColor,
    double? verticalPosition,
    double? opacity,
  }) {
    return SubtitleSettings(
      enabled: enabled ?? this.enabled,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      verticalPosition: verticalPosition ?? this.verticalPosition,
      opacity: opacity ?? this.opacity,
    );
  }
}
