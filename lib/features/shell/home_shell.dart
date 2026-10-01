import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/design_system.dart';
import '../camera/camera_screen.dart';
import '../chats/chats_screen.dart';
import '../map/map_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/me_screen.dart';

/// The camera-first home (Snapchat's spatial model): surfaces sit side by side and the app opens on the
/// camera, so creating is zero steps away. Swiping and the bottom bar drive the same pager, and each surface
/// keeps its state (scroll position, loaded data) while you move around.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = HomeTab.camera});

  final HomeTab initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum HomeTab {
  map(Icons.map_outlined, Icons.map_rounded, 'Map'),
  chats(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
  camera(Icons.camera_outlined, Icons.camera_rounded, 'Camera'),
  nearby(Icons.explore_outlined, Icons.explore_rounded, 'Nearby'),
  me(Icons.person_outline_rounded, Icons.person_rounded, 'Me');

  const HomeTab(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Media-first surfaces draw edge to edge, under a transparent bar.
  bool get immersive => this == camera || this == nearby;
}

class _HomeShellState extends State<HomeShell> {
  late final PageController _pages = PageController(
    initialPage: widget.initialTab.index,
  );
  late final ValueNotifier<double> _position = ValueNotifier(
    widget.initialTab.index.toDouble(),
  );

  @override
  void initState() {
    super.initState();
    _pages.addListener(() => _position.value = _pages.page ?? _position.value);
  }

  @override
  void dispose() {
    _pages.dispose();
    _position.dispose();
    super.dispose();
  }

  void _go(HomeTab tab) {
    final distance = ((_pages.page ?? 0) - tab.index).abs();
    if (distance > 1.5) {
      _pages.jumpToPage(tab.index); // far jumps skip the blur of passing pages
    } else {
      _pages.animateToPage(
        tab.index,
        duration: OdMotion.of(context, OdMotion.standard),
        curve: OdMotion.standardCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        body: PageView(
          controller: _pages,
          onPageChanged: (_) => HapticFeedback.selectionClick(),
          children: const [
            _KeepAlive(child: MapScreen()),
            _KeepAlive(child: ChatsScreen()),
            _KeepAlive(child: CameraScreen()),
            _KeepAlive(child: NearbyScreen()),
            _KeepAlive(child: MeScreen()),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<double>(
          valueListenable: _position,
          builder: (context, position, _) =>
              OdBottomBar(position: position, onSelect: _go),
        ),
      ),
    );
  }
}

/// Frosted bottom bar whose highlight follows the pager continuously (not just on page change), so swipes and
/// taps feel like one gesture system.
class OdBottomBar extends StatelessWidget {
  const OdBottomBar({
    super.key,
    required this.position,
    required this.onSelect,
  });

  final double position;
  final ValueChanged<HomeTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final nearest =
        HomeTab.values[position.round().clamp(0, HomeTab.values.length - 1)];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(OdSpace.x2, 0, OdSpace.x2, OdSpace.x1),
      child: OdFrosted(
        opacity: nearest.immersive ? 0.25 : 0.55,
        radius: OdRadius.xl,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final tab in HomeTab.values)
                Expanded(
                  child: _BarItem(
                    tab: tab,
                    // 1 when exactly on this page, fading to 0 one page away.
                    emphasis: (1 - (position - tab.index).abs()).clamp(
                      0.0,
                      1.0,
                    ),
                    onTap: () => onSelect(tab),
                    accent: c.brand,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.tab,
    required this.emphasis,
    required this.onTap,
    required this.accent,
  });

  final HomeTab tab;
  final double emphasis;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final selected = emphasis > 0.5;
    final color = Color.lerp(
      Colors.white.withValues(alpha: 0.7),
      Colors.white,
      emphasis,
    )!;
    if (tab == HomeTab.camera) {
      return OdPressable(
        onTap: onTap,
        semanticLabel: tab.label,
        haptic: OdHaptic.selection,
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: context.od.brandGradient,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25 + 0.3 * emphasis),
                  blurRadius: 12 + 8 * emphasis,
                ),
              ],
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      );
    }
    return OdPressable(
      onTap: onTap,
      semanticLabel: tab.label,
      haptic: OdHaptic.selection,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1 + 0.08 * emphasis,
            child: Icon(
              selected ? tab.selectedIcon : tab.icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: OdMotion.of(context, OdMotion.quick),
            width: selected ? 4 : 0,
            height: 4,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
