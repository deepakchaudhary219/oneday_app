import 'package:flutter/material.dart';
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
  final _deck = OdSwipeController();

  Future<bool> _decide(IncomingSignal signal, bool reveal) async {
    setState(
      () => _decided.add(signal.id),
    ); // optimistic: the card is already gone
    final repo = ref.read(signalsRepositoryProvider);
    try {
      if (reveal) {
        await repo.reveal(signal.id);
        if (!mounted) return true;
        HapticFeedback.heavyImpact();
        await showDialog<void>(
          context: context,
          builder: (_) => _Connected(name: signal.firstName, seed: signal.seed),
        );
        ref.invalidate(conversationsProvider);
      } else {
        await repo.letPass(signal.id);
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _decided.remove(signal.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That didn\'t go through. Try again.')),
      );
      return false;
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OdSpace.gutter,
                  ),
                  child: OdSwipeDeck<IncomingSignal>(
                    items: open,
                    itemKey: (s) => s.id,
                    controller: _deck,
                    rightLabel: 'REVEAL',
                    leftLabel: 'PASS',
                    onDecision: _decide,
                    builder: (context, signal) => _SignalCard(signal: signal),
                  ),
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
                        onPressed: () => _deck.swipe(right: false),
                      ),
                    ),
                    const SizedBox(width: OdSpace.x1_5),
                    Expanded(
                      child: OdButton(
                        label: 'Reveal',
                        icon: Icons.favorite_rounded,
                        onPressed: () => _deck.swipe(right: true),
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

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal});

  final IncomingSignal signal;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${signal.firstName} sent ${signal.reaction.label}. ${signal.sharedContext}. ${signal.timeLeft}.',
      child: Container(
        width: double.infinity,
        height: double.infinity,
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
            OdMediaArt(seed: signal.seed, activity: signal.activity),
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
                      // Their face, with the reaction they chose pinned to it.
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          OdAvatar(
                            name: signal.firstName,
                            seed: signal.seed,
                            size: 56,
                            ring: OdRing.live,
                          ),
                          Positioned(
                            right: -6,
                            bottom: -4,
                            child: Text(
                              signal.reaction.emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: OdSpace.x1_5),
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
          ],
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
