import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/veil_theme.dart';
import '../../library/screens/library_screen.dart';
import '../../folders/screens/folder_browser_screen.dart';
import '../../settings/screens/settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late PageController _pageController;
  late ValueNotifier<double> _pagePositionNotifier;

  final List<Widget> _screens = [
    const LibraryScreen(key: ValueKey<int>(0)),
    const FolderBrowserScreen(key: ValueKey<int>(1)),
    const SettingsScreen(key: ValueKey<int>(2)),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _pagePositionNotifier = ValueNotifier<double>(_currentIndex.toDouble());

    _pageController.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    if (_pageController.hasClients) {
      _pagePositionNotifier.value =
          _pageController.page ?? _currentIndex.toDouble();
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _pagePositionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    // Responsive width for floating pill
    final double pillWidth = isLandscape ? 380.0 : size.width - 48.0;
    // Calculate sliding indicator size
    const double paddingHorizontal = 12.0;
    final double itemWidth = (pillWidth - (paddingHorizontal * 2)) / 3;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 1. PageView for swiping between screens
          Positioned.fill(
            child: PageView(
              controller: _pageController,
              physics:
                  const BouncingScrollPhysics(), // Premium springy overscroll physics
              onPageChanged: (index) {
                if (_currentIndex != index) {
                  setState(() {
                    _currentIndex = index;
                  });
                }
              },
              children: _screens,
            ),
          ),

          // 2. Floating Pill Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 6.0,
                    sigmaY: 6.0,
                  ), // Lightweight blur
                  child: Container(
                    width: pillWidth,
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? Colors.black.withValues(alpha: 0.75)
                          : theme.colorScheme.surface.withValues(
                              alpha: 0.85,
                            ), // Glass color
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF1E1E1E)
                            : const Color(0xFFE5E7EB),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.5
                                : 0.08,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Sliding indicator capsule behind active tab item
                        ValueListenableBuilder<double>(
                          valueListenable: _pagePositionNotifier,
                          builder: (context, position, child) {
                            return Positioned(
                              left: paddingHorizontal + (position * itemWidth),
                              top: 10,
                              child: Container(
                                width: itemWidth,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.08,
                                  ), // subtle emerald active fill
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    width: 1,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // Tab Item Buttons
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: paddingHorizontal,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildNavItem(
                                0,
                                Icons.movie_filter_outlined,
                                Icons.movie_filter,
                                'Library',
                                theme,
                              ),
                              _buildNavItem(
                                1,
                                Icons.folder_open_outlined,
                                Icons.folder,
                                'Folders',
                                theme,
                              ),
                              _buildNavItem(
                                2,
                                Icons.settings_outlined,
                                Icons.settings,
                                'Settings',
                                theme,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData inactiveIcon,
    IconData activeIcon,
    String label,
    ThemeData theme,
  ) {
    return Expanded(
      child: SizedBox(
        height: 60,
        child: _NavBarTabButton(
          isSelected: _currentIndex == index,
          inactiveIcon: inactiveIcon,
          activeIcon: activeIcon,
          label: label,
          accentColor: theme.colorScheme.primary,
          onTap: () {
            setState(() {
              _currentIndex = index;
            });
            _pageController.animateToPage(
              index,
              duration: VeilMotion.standard,
              curve: VeilMotion.curve,
            );
          },
        ),
      ),
    );
  }
}

class _NavBarTabButton extends StatefulWidget {
  final bool isSelected;
  final IconData inactiveIcon;
  final IconData activeIcon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _NavBarTabButton({
    required this.isSelected,
    required this.inactiveIcon,
    required this.activeIcon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_NavBarTabButton> createState() => _NavBarTabButtonState();
}

class _NavBarTabButtonState extends State<_NavBarTabButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: VeilMotion.fast,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: VeilMotion.scaleButton)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: VeilMotion.curveSharp,
          ),
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
    final color = widget.isSelected
        ? widget.accentColor
        : (theme.brightness == Brightness.dark
              ? Colors.white38
              : Colors.black38);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _animController.forward(),
      onTapUp: (_) {
        _animController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _animController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: VeilMotion.fast,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Icon(
                widget.isSelected ? widget.activeIcon : widget.inactiveIcon,
                key: ValueKey<bool>(widget.isSelected),
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: VeilMotion.fast,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: widget.isSelected
                    ? FontWeight.w600
                    : FontWeight.w400,
                letterSpacing: 0.1,
              ),
              child: Text(widget.label),
            ),
          ],
        ),
      ),
    );
  }
}
