import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/providers/player_settings_provider.dart';
import '../../library/providers/media_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final settings = ref.watch(playerSettingsProvider);
    final notifier = ref.read(playerSettingsProvider.notifier);
    final subSettings = settings.subtitleSettings;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(
            'Settings',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16.0,
          8.0,
          16.0,
          100.0,
        ), // clear navigation bar clearance
        children: [
          _buildSectionHeader(theme, 'Playback'),
          _buildSwitchTile(
            title: 'Hardware Acceleration',
            subtitle: 'Use GPU decoding for smoother playback',
            value: settings.hwDecoding,
            onChanged: (val) => notifier.setHwDecoding(val),
          ),
          _buildSwitchTile(
            title: 'Remember Playback Position',
            subtitle: 'Automatically skip to last watched time',
            value: settings.autoResume,
            onChanged: (val) => notifier.setAutoResume(val),
          ),
          _buildSwitchTile(
            title: 'Auto-Play Next Video',
            subtitle: 'Start next folder video after current ends',
            value: settings.autoPlayNext,
            onChanged: (val) => notifier.setAutoPlayNext(val),
          ),

          _buildSelectionTile(
            title: 'Auto-Play Mode',
            subtitle: _getRepeatModeName(settings.repeatMode),
            onTap: () {
              _showSelectionDialog(
                title: 'Repeat Mode',
                options: ['Off', 'Repeat One', 'Repeat Folder'],
                currentValue: _getRepeatModeName(settings.repeatMode),
                onSelected: (val) {
                  notifier.setRepeatMode(_getRepeatModeCode(val));
                },
              );
            },
          ),

          _buildSectionHeader(theme, 'Subtitles'),
          _buildSliderTile(
            title: 'Subtitle Font Size',
            subtitle: '${subSettings.fontSize.toInt()} pt',
            value: subSettings.fontSize,
            min: 12.0,
            max: 28.0,
            onChanged: (val) {
              notifier.updateSubtitleSettings(
                subSettings.copyWith(fontSize: val),
              );
            },
          ),
          _buildSelectionTile(
            title: 'Subtitle Text Color',
            subtitle: _getColorName(subSettings.textColor),
            onTap: () {
              _showSelectionDialog(
                title: 'Text Color',
                options: ['White', 'Yellow', 'Green', 'Cyan'],
                currentValue: _getColorName(subSettings.textColor),
                onSelected: (val) {
                  notifier.updateSubtitleSettings(
                    subSettings.copyWith(textColor: _getColorHex(val)),
                  );
                },
              );
            },
          ),
          _buildSelectionTile(
            title: 'Subtitle Background',
            subtitle: _getBgName(subSettings.backgroundColor),
            onTap: () {
              _showSelectionDialog(
                title: 'Background Style',
                options: ['None', 'Semi-Transparent', 'Solid'],
                currentValue: _getBgName(subSettings.backgroundColor),
                onSelected: (val) {
                  notifier.updateSubtitleSettings(
                    subSettings.copyWith(backgroundColor: _getBgHex(val)),
                  );
                },
              );
            },
          ),
          _buildSliderTile(
            title: 'Subtitle Opacity',
            subtitle: '${(subSettings.opacity * 100).toInt()}%',
            value: subSettings.opacity,
            min: 0.1,
            max: 1.0,
            onChanged: (val) {
              notifier.updateSubtitleSettings(
                subSettings.copyWith(opacity: val),
              );
            },
          ),
          _buildSliderTile(
            title: 'Vertical Margins Padding',
            subtitle:
                '${(subSettings.verticalPosition * 100).toInt()}% from screen bottom',
            value: subSettings.verticalPosition,
            min: 0.01,
            max: 0.35,
            onChanged: (val) {
              notifier.updateSubtitleSettings(
                subSettings.copyWith(verticalPosition: val),
              );
            },
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Library'),
          _buildActionTile(
            title: 'Refresh Library',
            subtitle: 'Re-scan local storage for new folders and videos',
            icon: Icons.refresh_rounded,
            onTap: _refreshLibrary,
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Storage'),
          _buildSliderTile(
            title: 'Thumbnail Cache Size limit',
            subtitle: '${settings.thumbnailCacheSize} MB',
            value: settings.thumbnailCacheSize.toDouble(),
            min: 50.0,
            max: 500.0,
            onChanged: (val) {
              notifier.setThumbnailCacheSize(val.toInt());
            },
          ),
          _buildActionTile(
            title: 'Clear Thumbnail Cache',
            subtitle: 'Remove cached thumbnails to free up storage space',
            icon: Icons.cleaning_services_rounded,
            onTap: _clearThumbnailCache,
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Appearance'),
          _buildSelectionTile(
            title: 'Theme Mode',
            subtitle: settings.themeMode,
            onTap: () {
              _showSelectionDialog(
                title: 'Theme Mode',
                options: ['Dark', 'Light', 'System'],
                currentValue: settings.themeMode,
                onSelected: (val) => notifier.setThemeMode(val),
              );
            },
          ),
          _buildSwitchTile(
            title: 'AMOLED Pure Black',
            subtitle: 'Maximize battery life on OLED displays',
            value: settings.amoledPureBlack,
            onChanged: (val) => notifier.setAmoledPureBlack(val),
          ),
          _buildSelectionTile(
            title: 'Accent Color Swatch',
            subtitle: settings.themeAccent,
            onTap: () {
              _showSelectionDialog(
                title: 'Theme Accent',
                options: [
                  'Emerald',
                  'Ruby Red',
                  'Sapphire Blue',
                  'Amber Gold',
                  'Nothing Silver',
                ],
                currentValue: settings.themeAccent,
                onSelected: (val) => notifier.setThemeAccent(val),
              );
            },
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'Performance'),
          _buildSwitchTile(
            title: 'Battery Saver Mode',
            subtitle: 'Disable thumbnail loading and caching',
            value: settings.batterySaverMode,
            onChanged: (val) => notifier.setBatterySaverMode(val),
          ),
          const SizedBox(height: 16),

          _buildSectionHeader(theme, 'About'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Veil Player Version',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'v1.0.0 • Premium Offline Media Engine',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'STABLE',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          _buildActionTile(
            title: 'Open Source Licenses',
            subtitle: 'Credits and licensing for built-in libraries',
            icon: Icons.description_outlined,
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Veil Player',
                applicationVersion: '1.0.0',
              );
            },
          ),
          _buildActionTile(
            title: 'Privacy Policy',
            subtitle:
                'Read about our local-first, zero-data tracking guarantee',
            icon: Icons.privacy_tip_outlined,
            onTap: _showPrivacyDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  Widget _buildSelectionTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        size: 16,
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Icon(icon, color: theme.colorScheme.primary, size: 20),
    );
  }

  void _refreshLibrary() {
    final theme = Theme.of(context);
    ref.invalidate(foldersProvider);
    ref.invalidate(folderVideosProvider(null));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Text(
              'Library scan complete',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ],
        ),
        backgroundColor: theme.brightness == Brightness.dark
            ? const Color(0xFF111111)
            : const Color(0xFFF3F4F6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearThumbnailCache() async {
    final theme = Theme.of(context);
    final success = await ref
        .read(mediaRepositoryProvider)
        .clearThumbnailCache();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: success ? Colors.greenAccent : Colors.redAccent,
            ),
            const SizedBox(width: 8),
            Text(
              success
                  ? 'Thumbnail cache cleared successfully'
                  : 'Failed to clear thumbnail cache',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ],
        ),
        backgroundColor: theme.brightness == Brightness.dark
            ? const Color(0xFF111111)
            : const Color(0xFFF3F4F6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPrivacyDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          title: Text(
            'Privacy Guarantee',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Veil Player is a local-first video player. We do not transmit, analyze, or collect any logs, file details, or usage patterns. Your playback history and subtitle details remain securely stored inside private sandbox databases on your device.\n\nEnjoy pure, offline entertainment.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSelectionDialog({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSelected = opt == currentValue;
              return ListTile(
                title: Text(
                  opt,
                  style: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check,
                        color: theme.colorScheme.primary,
                        size: 20,
                      )
                    : null,
                onTap: () {
                  onSelected(opt);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _getRepeatModeName(String code) {
    switch (code) {
      case 'one':
        return 'Repeat One';
      case 'folder':
        return 'Repeat Folder';
      case 'off':
      default:
        return 'Off';
    }
  }

  String _getRepeatModeCode(String name) {
    switch (name) {
      case 'Repeat One':
        return 'one';
      case 'Repeat Folder':
        return 'folder';
      case 'Off':
      default:
        return 'off';
    }
  }

  String _getColorName(String hex) {
    switch (hex.toUpperCase()) {
      case '#FFFFFF':
        return 'White';
      case '#FFFF00':
        return 'Yellow';
      case '#00FF00':
        return 'Green';
      case '#00FFFF':
        return 'Cyan';
      default:
        return 'White';
    }
  }

  String _getColorHex(String name) {
    switch (name) {
      case 'White':
        return '#FFFFFF';
      case 'Yellow':
        return '#FFFF00';
      case 'Green':
        return '#00FF00';
      case 'Cyan':
        return '#00FFFF';
      default:
        return '#FFFFFF';
    }
  }

  String _getBgName(String hex) {
    if (hex == '#00000000') return 'None';
    if (hex == '#80000000') return 'Semi-Transparent';
    return 'Solid';
  }

  String _getBgHex(String name) {
    switch (name) {
      case 'None':
        return '#00000000';
      case 'Semi-Transparent':
        return '#80000000';
      case 'Solid':
        return '#FF000000';
      default:
        return '#00000000';
    }
  }
}
