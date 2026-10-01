import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

final pendingSignalsProvider = FutureProvider.autoDispose<List<IncomingSignal>>(
  (ref) => ref.watch(signalsRepositoryProvider).pending(),
);

/// The Signals digest: people who reached out, as a physical card stack. Swipe right to reveal (start a
/// conversation), left to let it pass. Passing is silent for the sender, so it never feels like rejection.
class SignalsScreen extends ConsumerStatefulWidget {
  const SignalsScreen({super.key});

  @override
  ConsumerState<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends ConsumerState<SignalsScreen> {
  final _decided = <String>{};

  Future<void> _decide(IncomingSignal signal, bool reveal) async {
    setState(
      () => _decided.add(signal.id),
    ); // optimistic: the card is already gone
    final repo = ref.read(signalsRepositoryProvider);
    try {
      if (reveal) {
        await repo.reveal(signal.id);
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        await showDialog<void>(
          context: context,
          builder: (_) => _Connected(name: signal.firstName, seed: signal.seed),
        );
        ref.invalidate(conversationsProvider);
      } else {
        await repo.letPass(signal.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _decided.remove(signal.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That didn\'t go through. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signals = ref.watch(pendingSignalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Signals')),
      body: signals.when(
        loading: () => const Center(
          child: OdSkeleton(width: 300, height: 420, radius: OdRadius.xl),
        ),
        error: (e, _) => Center(
          child: OdClosureCard(
            icon: Icons.wifi_off_rounded,
            title: 'Couldn\'t load signals',
            message: 'Check your connection.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(pendingSignalsProvider),
          ),
        ),
        data: (all) {
          final open = all.where((s) => !_decided.contains(s.id)).toList();
          if (open.isEmpty) {
            return const Center(
              child: OdClosureCard(
                title: 'All caught up',
                message: 'Signals wait for 48 hours, so there\'s never a rush. New ones show up here.',
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OdSpace.gutter),
                child: Text(
                  open.length == 1
                      ? '1 person reached out'
                      : '${open.length} people reached out',
                  style: context.type.bodyMedium,
                ),
              ),
              const SizedBox(height: OdSpace.x2),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = math.min(open.length, 3) - 1; i >= 0; i--)
                      _StackedCard(
                        key: ValueKey(open[i].id),
                        depth: i,
                        signal: open[i],
                        onDecided: (reveal) => _decide(open[i], reveal),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(OdSpace.gutter),
                child: Row(
                  children: [
                    Expanded(
                      child: OdButton(
                        label: 'Let it pass',
                        variant: OdButtonVariant.secondary,
                        onPressed: () => _decide(open.first, false),
                      ),
                    ),
                    const SizedBox(width: OdSpace.x1_5),
                    Expanded(
                      child: OdButton(
                        label: 'Reveal',
                        icon: Icons.favorite_rounded,
                        onPressed: () => _decide(open.first, true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StackedCard extends StatefulWidget {
  const _StackedCard({
    super.key,
    required this.depth,
    required this.signal,
    required this.onDecided,
  });

  final int depth;
  final IncomingSignal signal;
  final ValueChanged<bool> onDecided;

  @override
  State<_StackedCard> createState() => _StackedCardState();
}

class _StackedCardState extends State<_StackedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() {}));
  Offset _offset = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _thresholdBuzzed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset get _current => _controller.isAnimating
      ? Offset.lerp(_from, _to, _controller.value)!
      : _offset;

  void _release(Velocity velocity, double width) {
    final dx = _offset.dx;
    final vx = velocity.pixelsPerSecond.dx;
    final decided = dx.abs() > width * 0.28 || vx.abs() > 1100;
    _from = _offset;
    if (decided) {
      final right = (dx + vx * 0.1) > 0;
      _to = Offset(
        (right ? 1.5 : -1.5) * width,
        _offset.dy + velocity.pixelsPerSecond.dy * 0.15,
      );
      _controller
          .animateWith(SpringSimulation(OdMotion.spring, 0, 1, 0))
          .whenComplete(() => widget.onDecided(right));
    } else {
      _to = Offset.zero;
      _controller
          .animateWith(SpringSimulation(OdMotion.spring, 0, 1, 0))
          .whenComplete(() => _offset = Offset.zero);
    }
    _thresholdBuzzed = false;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final top = widget.depth == 0;
    final offset = _current;
    final tilt = offset.dx / width * 0.35;
    final intent = (offset.dx / (width * 0.28)).clamp(-1.0, 1.0);
    return AnimatedPadding(
      duration: OdMotion.of(context, OdMotion.standard),
      curve: OdMotion.enter,
      padding: EdgeInsets.only(top: widget.depth * 14.0),
      child: AnimatedScale(
        duration: OdMotion.of(context, OdMotion.standard),
        scale: 1 - widget.depth * 0.05,
        child: Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: tilt,
            child: GestureDetector(
              onPanUpdate: top
                  ? (d) {
                      setState(() => _offset += d.delta);
                      final past = _offset.dx.abs() > width * 0.28;
                      if (past && !_thresholdBuzzed) {
                        HapticFeedback.selectionClick(); // tells the thumb "release now decides"
                        _thresholdBuzzed = true;
                      } else if (!past) {
                        _thresholdBuzzed = false;
                      }
                    }
                  : null,
              onPanEnd: top ? (d) => _release(d.velocity, width) : null,
              child: _SignalCard(
                signal: widget.signal,
                intent: top ? intent : 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal, required this.intent});

  final IncomingSignal signal;

  /// -1 (pass) to 1 (reveal) while dragging.
  final double intent;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final size = MediaQuery.sizeOf(context);
    return Semantics(
      label:
          '${signal.firstName} sent ${signal.reaction.label}. ${signal.sharedContext}. ${signal.timeLeft}.',
      child: Container(
        width: size.width - OdSpace.gutter * 2,
        height: math.min(size.height * 0.56, 520),
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(OdRadius.xl),
          ),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OdMediaArt(seed: signal.seed + 100),
            const OdScrim(top: 0.1, bottom: 0.55),
            Positioned(
              left: OdSpace.x3,
              right: OdSpace.x3,
              bottom: OdSpace.x3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        signal.reaction.emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: OdSpace.x1),
                      Expanded(
                        child: Text(
                          '${signal.firstName}: "${signal.reaction.label}"',
                          style: context.type.headlineSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: OdSpace.x1),
                  Text(
                    signal.sharedContext,
                    style: context.type.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: OdSpace.x1_5),
                  Wrap(
                    spacing: OdSpace.x1,
                    runSpacing: OdSpace.x1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OdFrosted(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OdSpace.x1_5,
                          vertical: 6,
                        ),
                        child: Text(
                          '#${signal.activity}',
                          style: context.type.labelMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      OdTimePill(text: signal.timeLeft),
                    ],
                  ),
                ],
              ),
            ),
            // Decision hints fade in with the drag: what releasing will do, before it happens.
            Positioned(
              top: OdSpace.x3,
              left: OdSpace.x3,
              child: Opacity(
                opacity: intent.clamp(0.0, 1.0),
                child: _Stamp(label: 'REVEAL', color: c.safety),
              ),
            ),
            Positioned(
              top: OdSpace.x3,
              right: OdSpace.x3,
              child: Opacity(
                opacity: (-intent).clamp(0.0, 1.0),
                child: _Stamp(label: 'PASS', color: c.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OdSpace.x1_5,
        vertical: OdSpace.x0_5,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(OdRadius.sm),
      ),
      child: Text(
        label,
        style: context.type.titleLarge?.copyWith(
          color: color,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({required this.name, required this.seed});

  final String name;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.od.surface,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(OdRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(OdSpace.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: OdMotion.of(context, OdMotion.emphasized),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: OdAvatar(
                name: name,
                size: 88,
                ring: OdRing.live,
                seed: seed,
              ),
            ),
            const SizedBox(height: OdSpace.x2),
            Text(
              'You and $name are connected',
              textAlign: TextAlign.center,
              style: context.type.headlineSmall,
            ),
            const SizedBox(height: OdSpace.x1),
            Text(
              'Say hi while the moment\'s fresh. There\'s no timer on this.',
              textAlign: TextAlign.center,
              style: context.type.bodyMedium,
            ),
            const SizedBox(height: OdSpace.x3),
            OdButton(
              label: 'Say hi',
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
