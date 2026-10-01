import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/design_system.dart';

/// Where to share a capture: Friend Mode (Connections only, lenses allowed) or Discovery (nearby strangers,
/// live capture only, unfiltered).
enum ShareScope { friends, nearby }

/// A look applied live to the viewfinder (Friend Mode only: Nearby shares are live and unfiltered).
class Lens {
  const Lens(this.name, this.icon, this.matrix, this.swatch);

  final String name;
  final IconData icon;

  /// A 4x5 colour matrix, or null for no lens.
  final List<double>? matrix;
  final List<Color> swatch;

  static const none = Lens('None', Icons.block_rounded, null, [
    Color(0xFF3A3A44),
    Color(0xFF1C1C22),
  ]);

  static const all = [
    none,
    Lens(
      'Golden hour',
      Icons.wb_sunny_rounded,
      [
        1.15, 0.05, 0, 0, 12, //
        0.02, 1.0, 0, 0, 4,
        0, 0, 0.82, 0, -8,
        0, 0, 0, 1, 0,
      ],
      [Color(0xFFFFC46B), Color(0xFFFF7A59)],
    ),
    Lens(
      'Film',
      Icons.camera_roll_rounded,
      [
        0.9, 0.1, 0.05, 0, 10, //
        0.05, 0.88, 0.05, 0, 10,
        0.05, 0.1, 0.8, 0, 18,
        0, 0, 0, 1, 0,
      ],
      [Color(0xFFD8C7A6), Color(0xFF6E6152)],
    ),
    Lens(
      'Monsoon',
      Icons.water_drop_rounded,
      [
        0.85, 0, 0.1, 0, 0, //
        0, 1.0, 0.1, 0, 6,
        0.05, 0.1, 1.15, 0, 14,
        0, 0, 0, 1, 0,
      ],
      [Color(0xFF52E5C4), Color(0xFF2A7FDB)],
    ),
    Lens(
      'Noir',
      Icons.contrast_rounded,
      [
        0.4, 0.5, 0.15, 0, -10, //
        0.4, 0.5, 0.15, 0, -10,
        0.4, 0.5, 0.15, 0, -10,
        0, 0, 0, 1, 0,
      ],
      [Color(0xFFE8E8E8), Color(0xFF2A2A2A)],
    ),
    Lens(
      'Holi',
      Icons.palette_rounded,
      [
        1.25, 0, 0.15, 0, 6, //
        0, 0.95, 0.2, 0, 0,
        0.2, 0, 1.2, 0, 10,
        0, 0, 0, 1, 0,
      ],
      [Color(0xFFFF3D7F), Color(0xFF7B5CFF)],
    ),
  ];
}

/// The home surface, laid out the way people's thumbs already know from Snapchat: tools on the right rail,
/// lenses next to the shutter, memories on the left, your profile and search at the top. The viewfinder is a
/// stand-in until the `camera` plugin is wired (it needs a device); every control and transition here is real.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  ShareScope _scope = ShareScope.friends;
  bool _flash = false;
  bool _front = false;
  bool _grid = false;
  bool _lenses = false;
  int _timer = 0;
  Lens _lens = Lens.none;
  int _frame = 7;

  Lens get _activeLens => _scope == ShareScope.nearby ? Lens.none : _lens;

  Future<void> _captured({required bool video}) async {
    setState(() => _frame++);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: OdMotion.of(context, OdMotion.standard),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: OdMotion.enter),
          child: CapturePreview(
            seed: _frame,
            video: video,
            scope: _scope,
            lens: _activeLens,
            scene: _front ? SceneKind.cafe : SceneKind.mountains,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final lens = _activeLens;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Viewfinder(
          lens: lens,
          child: OdMediaArt(
            seed: _front ? 4 : 0,
            scene: _front ? SceneKind.cafe : SceneKind.mountains,
          ),
        ),
        if (_grid)
          const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
        const OdScrim(top: 0.2, bottom: 0.32),
        // Top: you, search, who sees it, add friends.
        Positioned(
          top: padding.top + OdSpace.x1,
          left: OdSpace.x1_5,
          right: OdSpace.x1_5,
          child: Row(
            children: [
              const OdAvatar(name: 'You', seed: 2, size: 40, ring: OdRing.live),
              const SizedBox(width: OdSpace.x1),
              _Glass(icon: Icons.search_rounded, label: 'Search', onTap: () {}),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _ScopeToggle(
                      value: _scope,
                      onChanged: (s) => setState(() => _scope = s),
                    ),
                  ),
                ),
              ),
              _Glass(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Add friends',
                onTap: () {},
              ),
            ],
          ),
        ),
        // Right rail: the camera's tools, one thumb-reach column.
        Positioned(
          top: padding.top + 64,
          right: OdSpace.x1_5,
          child: OdFrosted(
            radius: OdRadius.pill,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: Icons.cameraswitch_rounded,
                  label: 'Flip camera',
                  onTap: () => setState(() => _front = !_front),
                ),
                _RailButton(
                  icon: _flash
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  label: _flash ? 'Flash on' : 'Flash off',
                  active: _flash,
                  onTap: () => setState(() => _flash = !_flash),
                ),
                _RailButton(
                  icon: Icons.timer_outlined,
                  label: _timer == 0 ? 'Timer off' : 'Timer ${_timer}s',
                  badge: _timer == 0 ? null : '$_timer',
                  active: _timer > 0,
                  onTap: () => setState(
                    () => _timer = switch (_timer) {
                      0 => 3,
                      3 => 10,
                      _ => 0,
                    },
                  ),
                ),
                _RailButton(
                  icon: Icons.music_note_rounded,
                  label: 'Add music',
                  onTap: () {},
                ),
                _RailButton(
                  icon: Icons.grid_on_rounded,
                  label: _grid ? 'Hide grid' : 'Show grid',
                  active: _grid,
                  onTap: () => setState(() => _grid = !_grid),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom:
              padding.bottom +
              OdSpace.x2, // padding.bottom already includes the bar
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: OdMotion.of(context, OdMotion.quick),
                child: Text(
                  key: ValueKey('$_scope-${lens.name}'),
                  _scope == ShareScope.friends
                      ? (lens.matrix == null
                            ? 'Friends see it · lenses on'
                            : '${lens.name} · friends see it')
                      : 'Nearby people see it · live and unfiltered',
                  style: context.type.labelMedium?.copyWith(
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 12),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: OdMotion.of(context, OdMotion.standard),
                curve: OdMotion.standardCurve,
                child: _lenses && _scope == ShareScope.friends
                    ? Padding(
                        padding: const EdgeInsets.only(top: OdSpace.x1_5),
                        child: _LensStrip(
                          selected: _lens,
                          onSelect: (l) => setState(() => _lens = l),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: OdSpace.x1_5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MemoriesButton(seed: _frame),
                  const SizedBox(width: OdSpace.x4),
                  ShutterButton(
                    onPhoto: () => _captured(video: false),
                    onVideo: () => _captured(video: true),
                  ),
                  const SizedBox(width: OdSpace.x4),
                  _Glass(
                    icon: Icons.face_retouching_natural_rounded,
                    label: _lenses ? 'Hide lenses' : 'Lenses',
                    size: 48,
                    active: _lenses,
                    onTap: _scope == ShareScope.nearby
                        ? null
                        : () => setState(() => _lenses = !_lenses),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Applies the lens to whatever the camera shows.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.lens, required this.child});

  final Lens lens;
  final Widget child;

  @override
  Widget build(BuildContext context) => lens.matrix == null
      ? child
      : ColorFiltered(
          colorFilter: ColorFilter.matrix(lens.matrix!),
          child: child,
        );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        p,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// A frosted round button for controls floating over media.
class _Glass extends StatelessWidget {
  const _Glass({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 40,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return OdPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: OdSpace.minTap,
        child: Center(
          child: AnimatedContainer(
            duration: OdMotion.of(context, OdMotion.quick),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white
                  : Colors.black.withValues(alpha: 0.32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(
              icon,
              size: size * 0.5,
              color: active ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return OdPressable(
      onTap: onTap,
      semanticLabel: label,
      haptic: OdHaptic.selection,
      child: SizedBox.square(
        dimension: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: active ? const Color(0xFFFFE066) : Colors.white,
            ),
            if (badge != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Text(
                  badge!,
                  style: context.type.labelSmall?.copyWith(
                    color: const Color(0xFFFFE066),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Last capture as a thumbnail: one tap back into Memories.
class _MemoriesButton extends StatelessWidget {
  const _MemoriesButton({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    return OdPressable(
      onTap: () {},
      semanticLabel: 'Memories',
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: OdMediaArt(
          seed: seed,
          scene: SceneKind.values[seed % SceneKind.values.length],
        ),
      ),
    );
  }
}

class _LensStrip extends StatelessWidget {
  const _LensStrip({required this.selected, required this.onSelect});

  final Lens selected;
  final ValueChanged<Lens> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: OdSpace.gutter),
        itemCount: Lens.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: OdSpace.x1_5),
        itemBuilder: (context, i) {
          final lens = Lens.all[i];
          final on = lens == selected;
          return OdPressable(
            onTap: () => onSelect(lens),
            haptic: OdHaptic.selection,
            semanticLabel: '${lens.name} lens${on ? ', selected' : ''}',
            child: Column(
              children: [
                AnimatedContainer(
                  duration: OdMotion.of(context, OdMotion.quick),
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: on ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: lens.swatch,
                      ),
                    ),
                    child: Icon(lens.icon, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lens.name,
                  style: context.type.labelSmall?.copyWith(
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({required this.value, required this.onChanged});

  final ShareScope value;
  final ValueChanged<ShareScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return OdFrosted(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final scope in ShareScope.values)
            OdPressable(
              onTap: () => onChanged(scope),
              haptic: OdHaptic.selection,
              semanticLabel: scope == ShareScope.friends
                  ? 'Share with friends'
                  : 'Share nearby',
              child: AnimatedContainer(
                duration: OdMotion.of(context, OdMotion.quick),
                curve: OdMotion.standardCurve,
                padding: const EdgeInsets.symmetric(
                  horizontal: OdSpace.x2,
                  vertical: OdSpace.x1,
                ),
                decoration: BoxDecoration(
                  color: value == scope ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(OdRadius.pill),
                ),
                child: Text(
                  scope == ShareScope.friends ? 'Friends' : 'Nearby',
                  style: context.type.labelMedium?.copyWith(
                    color: value == scope ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tap for a photo, hold for a video (up to 15 s, with a progress ring), the gesture people already know.
class ShutterButton extends StatefulWidget {
  const ShutterButton({
    super.key,
    required this.onPhoto,
    required this.onVideo,
  });

  final VoidCallback onPhoto;
  final VoidCallback onVideo;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _record =
      AnimationController(vsync: this, duration: const Duration(seconds: 15))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _stop();
        });
  bool _pressed = false;

  void _stop() {
    if (!_record.isAnimating && _record.value == 0) return;
    _record.reset();
    setState(() => _pressed = false);
    widget.onVideo();
  }

  @override
  void dispose() {
    _record.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Semantics(
      button: true,
      label: 'Shutter. Tap for a photo, hold to record.',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() => _pressed = false);
          widget.onPhoto();
        },
        onLongPressStart: (_) {
          HapticFeedback.heavyImpact();
          setState(() => _pressed = true);
          _record.forward(from: 0);
        },
        onLongPressEnd: (_) => _stop(),
        child: AnimatedScale(
          scale: _pressed ? 1.18 : 1,
          duration: OdMotion.of(context, OdMotion.quick),
          curve: OdMotion.enter,
          child: SizedBox.square(
            dimension: 84,
            child: AnimatedBuilder(
              animation: _record,
              builder: (context, _) => CustomPaint(
                painter: _RingPainter(progress: _record.value, color: c.live),
                child: Center(
                  child: AnimatedContainer(
                    duration: OdMotion.of(context, OdMotion.quick),
                    width: _record.isAnimating ? 34 : 64,
                    height: _record.isAnimating ? 34 : 64,
                    decoration: BoxDecoration(
                      color: _record.isAnimating ? c.live : Colors.white,
                      borderRadius: BorderRadius.circular(
                        _record.isAnimating ? OdRadius.sm : OdRadius.pill,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Colors.white;
    canvas.drawArc(rect.deflate(3), 0, 6.283, false, base);
    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect.deflate(3), -1.5708, 6.283 * progress, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// After capture: preview, then share. Nearby shares carry the Live badge (captured in-app, unfiltered).
class CapturePreview extends StatelessWidget {
  const CapturePreview({
    super.key,
    required this.seed,
    required this.video,
    required this.scope,
    this.lens = Lens.none,
    this.scene,
  });

  final int seed;
  final bool video;
  final ShareScope scope;
  final Lens lens;
  final SceneKind? scene;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Viewfinder(
            lens: lens,
            child: OdMediaArt(seed: seed, scene: scene),
          ),
          const OdScrim(),
          Positioned(
            top: padding.top + OdSpace.x1,
            left: OdSpace.gutter,
            right: OdSpace.gutter,
            child: Row(
              children: [
                OdIconButton(
                  icon: Icons.close_rounded,
                  semanticLabel: 'Discard',
                  background: Colors.black26,
                  foreground: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                if (scope == ShareScope.nearby) const OdLiveBadge(),
                if (video) ...[
                  const SizedBox(width: OdSpace.x1),
                  const OdLiveBadge(label: 'VIDEO'),
                ],
              ],
            ),
          ),
          Positioned(
            left: OdSpace.gutter,
            right: OdSpace.gutter,
            bottom: padding.bottom + OdSpace.x3,
            child: Row(
              children: [
                Expanded(
                  child: OdButton(
                    label: 'Save',
                    icon: Icons.download_rounded,
                    variant: OdButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: OdSpace.x1_5),
                Expanded(
                  flex: 2,
                  child: OdButton(
                    label: scope == ShareScope.friends
                        ? 'Share with friends'
                        : 'Share nearby',
                    icon: Icons.send_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Shared. It disappears in 24 hours.'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
