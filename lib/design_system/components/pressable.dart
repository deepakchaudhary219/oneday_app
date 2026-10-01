import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/motion.dart';

enum OdHaptic { none, selection, light, medium }

/// The one way to make something tappable. It answers within a frame: scales to 0.96 while pressed, fires a
/// haptic on release, and exposes a button to screen readers.
class OdPressable extends StatefulWidget {
  const OdPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.haptic = OdHaptic.light,
    this.semanticLabel,
    this.pressedScale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final OdHaptic haptic;
  final String? semanticLabel;
  final double pressedScale;

  @override
  State<OdPressable> createState() => _OdPressableState();
}

class _OdPressableState extends State<OdPressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  static void feedback(OdHaptic haptic) {
    switch (haptic) {
      case OdHaptic.none:
        break;
      case OdHaptic.selection:
        HapticFeedback.selectionClick();
      case OdHaptic.light:
        HapticFeedback.lightImpact();
      case OdHaptic.medium:
        HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                feedback(widget.haptic);
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _set(false);
                feedback(OdHaptic.medium);
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1,
          duration: OdMotion.of(context, OdMotion.instant),
          curve: OdMotion.standardCurve,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: OdMotion.of(context, OdMotion.quick),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
