import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/design_system.dart';

/// Where to share a capture: Friend Mode (Connections only, lenses allowed) or Discovery (nearby strangers,
/// live capture only, unfiltered).
enum ShareScope { friends, nearby }

/// The home surface. The viewfinder is a placeholder until the `camera` plugin is wired (it needs a device);
/// every control, gesture and transition here is real.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  ShareScope _scope = ShareScope.friends;
  bool _flash = false;
  bool _front = false;
  int _frame = 7;

  Future<void> _captured({required bool video}) async {
    setState(() => _frame++);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: OdMotion.of(context, OdMotion.standard),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: OdMotion.enter),
          child: CapturePreview(seed: _frame, video: video, scope: _scope),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        OdMediaArt(seed: _front ? 4 : 0),
        const OdScrim(top: 0.18, bottom: 0.3),
        Positioned(
          top: padding.top + OdSpace.x1,
          left: OdSpace.gutter,
          right: OdSpace.gutter,
          child: Row(
            children: [
              OdIconButton(
                icon: _flash ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                semanticLabel: _flash ? 'Flash on' : 'Flash off',
                background: Colors.black26,
                foreground: Colors.white,
                onPressed: () => setState(() => _flash = !_flash),
              ),
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
              OdIconButton(
                icon: Icons.cameraswitch_rounded,
                semanticLabel: 'Flip camera',
                background: Colors.black26,
                foreground: Colors.white,
                onPressed: () => setState(() => _front = !_front),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: padding.bottom + 104,
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: OdMotion.of(context, OdMotion.quick),
                child: Text(
                  key: ValueKey(_scope),
                  _scope == ShareScope.friends
                      ? 'Friends see it · lenses on'
                      : 'Nearby people see it · live and unfiltered',
                  style: context.type.labelMedium?.copyWith(
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 12),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: OdSpace.x2),
              ShutterButton(
                onPhoto: () => _captured(video: false),
                onVideo: () => _captured(video: true),
              ),
            ],
          ),
        ),
      ],
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
  });

  final int seed;
  final bool video;
  final ShareScope scope;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          OdMediaArt(seed: seed),
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
