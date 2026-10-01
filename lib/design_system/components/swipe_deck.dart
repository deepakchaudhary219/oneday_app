import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens/motion.dart';
import '../tokens/spacing.dart';

/// Lets buttons perform the same fly-out a swipe does, so tapping and swiping feel like one gesture.
class OdSwipeController {
  _OdSwipeDeckState<Object?>? _deck;

  /// Swipes the top card right ([right] true) or left; does nothing when the deck is empty or busy.
  void swipe({required bool right}) => _deck?._swipeTop(right);
}

/// A physical card stack (Tinder's interaction, with OneDay's limits): drag the top card, it tilts with the thumb,
/// a stamp says what releasing will do, a tick of haptics marks the threshold, and a spring settles everything.
///
/// [onDecision] runs after the card has flown out. Returning false brings the card back (the person cancelled,
/// or the request failed); returning true leaves it to the parent to drop the item from [items].
class OdSwipeDeck<T> extends StatefulWidget {
  const OdSwipeDeck({
    super.key,
    required this.items,
    required this.itemKey,
    required this.builder,
    required this.onDecision,
    this.controller,
    this.rightLabel = 'YES',
    this.leftLabel = 'PASS',
    this.rightColor,
    this.leftColor,
    this.visible = 3,
  });

  final List<T> items;
  final Object Function(T item) itemKey;
  final Widget Function(BuildContext context, T item) builder;
  final Future<bool> Function(T item, bool right) onDecision;
  final OdSwipeController? controller;
  final String rightLabel;
  final String leftLabel;
  final Color? rightColor;
  final Color? leftColor;
  final int visible;

  @override
  State<OdSwipeDeck<T>> createState() => _OdSwipeDeckState<T>();
}

class _OdSwipeDeckState<T> extends State<OdSwipeDeck<T>> {
  final _topKey = GlobalKey<_DeckCardState>();

  @override
  void initState() {
    super.initState();
    widget.controller?._deck = this as _OdSwipeDeckState<Object?>;
  }

  @override
  void didUpdateWidget(OdSwipeDeck<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._deck = null;
      widget.controller?._deck = this as _OdSwipeDeckState<Object?>;
    }
  }

  @override
  void dispose() {
    widget.controller?._deck = null;
    super.dispose();
  }

  void _swipeTop(bool right) => _topKey.currentState?.flyOut(right);

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final count = math.min(items.length, widget.visible);
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = count - 1; i >= 0; i--)
            Positioned.fill(
              child: _DeckCard(
                key: i == 0 ? _topKey : ValueKey(widget.itemKey(items[i])),
                depth: i,
                width: box.maxWidth,
                rightLabel: widget.rightLabel,
                leftLabel: widget.leftLabel,
                rightColor: widget.rightColor ?? context.od.safety,
                leftColor: widget.leftColor ?? context.od.textTertiary,
                onDecision: (right) => widget.onDecision(items[i], right),
                child: KeyedSubtree(
                  key: ValueKey(widget.itemKey(items[i])),
                  child: widget.builder(context, items[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckCard extends StatefulWidget {
  const _DeckCard({
    super.key,
    required this.depth,
    required this.width,
    required this.child,
    required this.onDecision,
    required this.rightLabel,
    required this.leftLabel,
    required this.rightColor,
    required this.leftColor,
  });

  final int depth;
  final double width;
  final Widget child;
  final Future<bool> Function(bool right) onDecision;
  final String rightLabel;
  final String leftLabel;
  final Color rightColor;
  final Color leftColor;

  @override
  State<_DeckCard> createState() => _DeckCardState();
}

class _DeckCardState extends State<_DeckCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController.unbounded(vsync: this)..addListener(
        () => setState(() => _offset = Offset.lerp(_from, _to, _anim.value)!),
      );
  Offset _offset = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _busy = false;
  bool _buzzed = false;

  double get _threshold => widget.width * 0.28;

  @override
  void didUpdateWidget(_DeckCard old) {
    super.didUpdateWidget(old);
    // A new item moved into this slot (the old top card was decided): start centred.
    if ((old.child.key != widget.child.key) && !_anim.isAnimating) {
      _offset = Offset.zero;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _springTo(Offset target, {double velocity = 0}) {
    _from = _offset;
    _to = target;
    return _anim
        .animateWith(SpringSimulation(OdMotion.spring, 0, 1, velocity))
        .orCancel
        .catchError((_) {});
  }

  Future<void> flyOut(bool right, {Offset? velocity}) async {
    if (_busy) return;
    _busy = true;
    HapticFeedback.mediumImpact();
    final dy = _offset.dy + (velocity?.dy ?? 0) * 0.15;
    await _springTo(Offset((right ? 1.6 : -1.6) * widget.width, dy));
    final kept = await widget.onDecision(right);
    if (!mounted) return;
    if (!kept) {
      await _springTo(Offset.zero);
    }
    _busy = false;
  }

  void _release(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    final decided = _offset.dx.abs() > _threshold || v.dx.abs() > 1100;
    _buzzed = false;
    if (decided) {
      flyOut((_offset.dx + v.dx * 0.1) > 0, velocity: v);
    } else {
      _springTo(Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.depth == 0;
    final intent = top ? (_offset.dx / _threshold).clamp(-1.0, 1.0) : 0.0;
    // Cards behind peek out below and rise into place as the top one leaves.
    return AnimatedPadding(
      duration: OdMotion.of(context, OdMotion.standard),
      curve: OdMotion.enter,
      padding: EdgeInsets.only(top: widget.depth * 10.0),
      child: AnimatedScale(
        duration: OdMotion.of(context, OdMotion.standard),
        curve: OdMotion.enter,
        scale: 1 - widget.depth * 0.04,
        alignment: Alignment.topCenter,
        child: Transform.translate(
          offset: _offset,
          child: Transform.rotate(
            angle: _offset.dx / widget.width * 0.3,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onPanUpdate: top && !_busy
                  ? (d) {
                      setState(() => _offset += d.delta);
                      final past = _offset.dx.abs() > _threshold;
                      if (past && !_buzzed) {
                        HapticFeedback.selectionClick(); // "releasing now decides"
                        _buzzed = true;
                      } else if (!past) {
                        _buzzed = false;
                      }
                    }
                  : null,
              onPanEnd: top && !_busy ? _release : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  if (top) ...[
                    Positioned(
                      top: OdSpace.x6,
                      left: OdSpace.x3,
                      child: _Stamp(
                        label: widget.rightLabel,
                        color: widget.rightColor,
                        opacity: intent,
                        angle: -0.25,
                      ),
                    ),
                    Positioned(
                      top: OdSpace.x6,
                      right: OdSpace.x3,
                      child: _Stamp(
                        label: widget.leftLabel,
                        color: widget.leftColor,
                        opacity: -intent,
                        angle: 0.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    required this.angle,
  });

  final String label;
  final Color color;
  final double opacity;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final o = opacity.clamp(0.0, 1.0);
    if (o == 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: o,
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: 0.8 + 0.2 * o,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: OdSpace.x1_5,
                vertical: OdSpace.x0_5,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: context.type.headlineSmall?.copyWith(
                  color: color,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
