import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../design_system/design_system.dart';

final signalsLeftProvider = FutureProvider.autoDispose<SignalBudget>(
  (ref) => ref.watch(nearbyRepositoryProvider).budget(),
);

/// People sharing moments around you, as a card deck (Tinder's gesture vocabulary) built on moments instead of
/// profiles: the photo is what they're doing right now, the chips are what you share, and a Signal costs one of
/// a few a day, so every right swipe means something. The deck ends; there is no infinite stack.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  final _deck = OdSwipeController();
  final _gone = <String>{};
  String? _sentTo;

  Future<bool> _decide(NearbyMoment m, bool right) async {
    if (!right) {
      setState(() => _gone.add(m.id)); // passing is private and free
      return true;
    }
    final left = ref.read(signalsLeftProvider).value?.remaining ?? 0;
    final reaction = await showOdSheet<SignalReaction>(
      context,
      builder: (_) => _SignalSheet(moment: m, left: left),
    );
    if (reaction == null || !mounted) return false;
    setState(() {
      _gone.add(m.id); // optimistic
      _sentTo = m.firstName;
    });
    try {
      await ref.read(nearbyRepositoryProvider).sendSignal(m.id, reaction);
      HapticFeedback.heavyImpact();
      ref.invalidate(signalsLeftProvider);
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _sentTo = null);
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _gone.remove(m.id);
        _sentTo = null;
      });
      if (e is ApiError && e.code.endsWith('VERIFICATION_REQUIRED')) {
        // Progressive verification: the first contact action is where we ask; the signal isn't spent.
        final verified = await context.push<bool>('/verify');
        if (verified == true && mounted) _deck.swipe(right: true);
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t send. Your signal wasn\'t used.'),
        ),
      );
      return false;
    }
  }

  void _why(NearbyMoment m) => showOdSheet<void>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OdAvatar(name: m.firstName, seed: m.seed, size: 48),
            const SizedBox(width: OdSpace.x1_5),
            Expanded(
              child: Text(
                'Why you\'re seeing ${m.firstName}',
                style: context.type.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: OdSpace.x2),
        Text(
          m.why ?? 'They shared a moment near you recently.',
          style: context.type.bodyLarge,
        ),
        const SizedBox(height: OdSpace.x1),
        Text(
          'Nearby shows moments from the last day, by distance band only. Nobody sees where you are.',
          style: context.type.bodyMedium,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final moments = ref.watch(nearbyMomentsProvider);
    final padding = MediaQuery.paddingOf(context);
    final c = context.od;
    return ColoredBox(
      color: c.canvas,
      child: Padding(
        // The shell extends the body under the bar, so padding.bottom already includes it.
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: padding.bottom + OdSpace.x1,
        ),
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: moments.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(OdSpace.x1_5),
                  child: OdSkeleton(radius: 28),
                ),
                error: (e, _) => Center(child: _ErrorState(error: e)),
                data: (all) {
                  final open = all.where((m) => !_gone.contains(m.id)).toList();
                  return Stack(
                    children: [
                      if (open.isEmpty)
                        const Center(child: _CaughtUp())
                      else
                        Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  OdSpace.x1_5,
                                  OdSpace.x1,
                                  OdSpace.x1_5,
                                  0,
                                ),
                                child: OdSwipeDeck<NearbyMoment>(
                                  items: open,
                                  itemKey: (m) => m.id,
                                  controller: _deck,
                                  rightLabel: 'SIGNAL',
                                  leftLabel: 'PASS',
                                  rightColor: c.brand,
                                  leftColor: Colors.white,
                                  onDecision: _decide,
                                  builder: (context, m) =>
                                      _MomentCard(moment: m),
                                ),
                              ),
                            ),
                            _Actions(
                              onPass: () => _deck.swipe(right: false),
                              onSignal: () => _deck.swipe(right: true),
                              onWhy: () => _why(open.first),
                            ),
                          ],
                        ),
                      if (_sentTo != null) _SentToast(name: _sentTo!),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(signalsLeftProvider).value;
    final c = context.od;
    final label = budget == null
        ? 'Signals'
        : budget.remaining > 0
        ? '${budget.remaining} ${budget.remaining == 1 ? 'signal' : 'signals'} left today'
        : budget.nextFreesAt == null
        ? 'No signals left today'
        : 'More at ${TimeOfDay.fromDateTime(budget.nextFreesAt!.toLocal()).format(context)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OdSpace.gutter,
        OdSpace.x1,
        OdSpace.x1_5,
        OdSpace.x0_5,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Nearby',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.headlineSmall,
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.55,
            ),
            child: Semantics(
              label: label,
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: OdSpace.x1_5,
                  vertical: OdSpace.x1,
                ),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(OdRadius.pill),
                  border: Border.all(color: c.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (r) => c.brandGradient.createShader(r),
                      child: const Icon(
                        Icons.waving_hand_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        budget == null
                            ? '–'
                            : (budget.remaining > 0
                                  ? '${budget.remaining} left'
                                  : label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The moment as a full-bleed card: media first, then who, how far, and what you share.
class _MomentCard extends StatelessWidget {
  const _MomentCard({required this.moment});

  final NearbyMoment moment;

  @override
  Widget build(BuildContext context) {
    final m = moment;
    return Semantics(
      label:
          '${m.firstName}, ${m.activity}, ${m.distance} away${m.prompt == null ? '' : '. Answering: ${m.prompt}'}',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(28),
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 440;
              return MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OdMedia(
                      seed: m.seed,
                      url: m.previewUrl,
                      activity: m.activity,
                    ),
                    const OdScrim(top: 0.22, bottom: 0.62),
                    Positioned(
                      top: OdSpace.x1_5,
                      left: OdSpace.x1_5,
                      right: OdSpace.x1_5,
                      child: Row(
                        children: [
                          if (m.liveCapture) ...[
                            const OdLiveBadge(),
                            const SizedBox(width: OdSpace.x1),
                          ],
                          if (m.postedAgo != null)
                            OdFrosted(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Text(
                                '${m.postedAgo} ago',
                                style: context.type.labelMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: OdSpace.x2,
                      right: OdSpace.x2,
                      bottom: OdSpace.x2,
                      top: OdSpace.x6,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: SizedBox(
                            width: box.maxWidth - OdSpace.x4,
                            child: _MomentDetails(moment: m, compact: compact),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MomentDetails extends StatelessWidget {
  const _MomentDetails({required this.moment, required this.compact});

  final NearbyMoment moment;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m = moment;
    const white = Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m.prompt != null && !compact) ...[
          OdFrosted(
            radius: OdRadius.lg,
            padding: const EdgeInsets.fromLTRB(
              OdSpace.x2,
              OdSpace.x1_5,
              OdSpace.x2,
              OdSpace.x1_5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TODAY\'S PROMPT',
                  style: context.type.labelSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  m.prompt!,
                  style: context.type.titleMedium?.copyWith(color: white),
                ),
              ],
            ),
          ),
          const SizedBox(height: OdSpace.x1_5),
        ],
        Row(
          children: [
            OdAvatar(
              name: m.firstName,
              seed: m.seed,
              size: 42,
              ring: OdRing.live,
            ),
            const SizedBox(width: OdSpace.x1_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.displaySmall?.copyWith(
                      color: white,
                      fontSize: 32,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.near_me_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${m.distance} away',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: OdSpace.x1),
        Row(
          children: [
            const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFFFC94D)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                m.activity,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.titleMedium?.copyWith(color: white),
              ),
            ),
          ],
        ),
        if (m.tags.isNotEmpty && !compact) ...[
          const SizedBox(height: OdSpace.x1_5),
          Wrap(
            spacing: OdSpace.x1,
            runSpacing: OdSpace.x1,
            children: [
              for (final t in m.tags)
                OdFrosted(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    t,
                    style: context.type.labelMedium?.copyWith(color: white),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tinder's three-button row, sized by importance: Pass and Why are equal, Signal is the hero.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.onPass,
    required this.onSignal,
    required this.onWhy,
  });

  final VoidCallback onPass;
  final VoidCallback onSignal;
  final VoidCallback onWhy;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OdSpace.x1_5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundAction(
            icon: Icons.close_rounded,
            label: 'Pass',
            size: 58,
            iconColor: const Color(0xFFFF5A6E),
            onTap: onPass,
          ),
          const SizedBox(width: OdSpace.x3),
          _RoundAction(
            icon: Icons.waving_hand_rounded,
            label: 'Signal',
            size: 74,
            gradient: c.brandGradient,
            iconColor: Colors.white,
            onTap: onSignal,
          ),
          const SizedBox(width: OdSpace.x3),
          _RoundAction(
            icon: Icons.auto_awesome_rounded,
            label: 'Why you see this',
            size: 58,
            iconColor: const Color(0xFF4DD6C1),
            onTap: onWhy,
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.size,
    required this.iconColor,
    required this.onTap,
    this.gradient,
  });

  final IconData icon;
  final String label;
  final double size;
  final Color iconColor;
  final Gradient? gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return OdPressable(
      onTap: onTap,
      semanticLabel: label,
      pressedScale: 0.88,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gradient == null ? c.surfaceRaised : null,
          gradient: gradient,
          border: gradient == null ? Border.all(color: c.outline) : null,
          boxShadow: [
            BoxShadow(
              color: (gradient == null ? Colors.black : c.brand).withValues(
                alpha: 0.35,
              ),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.44),
      ),
    );
  }
}

class _SentToast extends StatelessWidget {
  const _SentToast({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: OdSpace.x3,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: OdMotion.of(context, OdMotion.emphasized),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: OdSpace.x2,
              vertical: OdSpace.x1_5,
            ),
            decoration: BoxDecoration(
              gradient: context.od.brandGradient,
              borderRadius: BorderRadius.circular(OdRadius.pill),
            ),
            child: Text(
              'Signal sent to $name',
              style: context.type.labelLarge?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (error is LocationRequired) {
      return OdClosureCard(
        icon: Icons.near_me_rounded,
        title: 'See who\'s around',
        message: 'Share your area while the app is open. People see a distance band, never where you are.',
        actionLabel: 'Share my area',
        onAction: () async {
          final ok = await ref.read(locationShareProvider).share();
          if (!context.mounted) return;
          if (ok) {
            ref.invalidate(nearbyMomentsProvider);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Couldn\'t get your location. Check location permission.',
                ),
              ),
            );
          }
        },
      );
    }
    return OdClosureCard(
      icon: Icons.wifi_off_rounded,
      title: 'Couldn\'t load who\'s nearby',
      message: error is ApiError
          ? (error as ApiError).detail
          : 'Check your connection and try again.',
      actionLabel: 'Try again',
      onAction: () => ref.invalidate(nearbyMomentsProvider),
    );
  }
}

/// Signals carry a reaction, never free text: approaching costs something and can't be used to harass.
class _SignalSheet extends StatelessWidget {
  const _SignalSheet({required this.moment, required this.left});

  final NearbyMoment moment;
  final int left;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OdAvatar(
              name: moment.firstName,
              seed: moment.seed,
              size: 52,
              ring: OdRing.live,
            ),
            const SizedBox(width: OdSpace.x1_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Send ${moment.firstName} a signal',
                    style: context.type.titleLarge,
                  ),
                  Text(
                    left > 0 ? '$left left today' : 'None left today',
                    style: context.type.labelMedium?.copyWith(color: c.brand),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: OdSpace.x1_5),
        Text(
          left > 0
              ? 'They\'ll see your reaction and first name. If they reveal too, you can chat.'
              : 'You\'ve used today\'s signals. They refresh tomorrow, so the ones you send matter.',
          style: context.type.bodyMedium,
        ),
        const SizedBox(height: OdSpace.x2),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: OdSpace.x1,
          crossAxisSpacing: OdSpace.x1,
          childAspectRatio: 1.9,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final r in SignalReaction.values)
              OdPressable(
                onTap: left > 0 ? () => Navigator.of(context).pop(r) : null,
                semanticLabel: r.label,
                child: Opacity(
                  opacity: left > 0 ? 1 : 0.4,
                  child: OdCard(
                    padding: const EdgeInsets.all(OdSpace.x1_5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r.emoji, style: const TextStyle(fontSize: 26)),
                        Text(
                          r.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp();

  @override
  Widget build(BuildContext context) {
    return const OdClosureCard(
      title: 'That\'s everyone nearby for now',
      message: 'New moments appear as people share them. Meanwhile, maybe go make one of your own.',
    );
  }
}
