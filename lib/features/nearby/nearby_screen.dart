import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/repositories.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

final signalsLeftProvider = FutureProvider.autoDispose<SignalBudget>(
  (ref) => ref.watch(nearbyRepositoryProvider).budget(),
);

/// Nearby moments, one per screen (TikTok's immersion) but bounded: the pager ends with a closure card, because
/// the people near you right now are a finite, real set and the app says so.
class NearbyScreen extends ConsumerWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments = ref.watch(nearbyMomentsProvider);
    return ColoredBox(
      color: Colors.black,
      child: moments.when(
        loading: () => const _NearbyLoading(),
        error: (e, _) => Center(
          child: e is LocationRequired
              ? OdClosureCard(
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
                )
              : OdClosureCard(
                  icon: Icons.wifi_off_rounded,
                  title: 'Couldn\'t load who\'s nearby',
                  message: e is ApiError
                      ? e.detail
                      : 'Check your connection and try again.',
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(nearbyMomentsProvider),
                ),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(nearbyMomentsProvider),
          child: PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: list.length + 1,
            itemBuilder: (context, i) => i == list.length
                ? const _CaughtUp()
                : _MomentPage(moment: list[i], index: i, total: list.length),
          ),
        ),
      ),
    );
  }
}

class _MomentPage extends ConsumerStatefulWidget {
  const _MomentPage({
    required this.moment,
    required this.index,
    required this.total,
  });

  final NearbyMoment moment;
  final int index;
  final int total;

  @override
  ConsumerState<_MomentPage> createState() => _MomentPageState();
}

class _MomentPageState extends ConsumerState<_MomentPage> {
  SignalReaction? _sent;

  Future<void> _signal() async {
    final left = ref.read(signalsLeftProvider).value?.remaining ?? 0;
    final reaction = await showOdSheet<SignalReaction>(
      context,
      builder: (_) => _SignalSheet(moment: widget.moment, left: left),
    );
    if (reaction == null || !mounted) return;
    setState(() => _sent = reaction); // optimistic
    try {
      await ref
          .read(nearbyRepositoryProvider)
          .sendSignal(widget.moment.id, reaction);
      ref.invalidate(signalsLeftProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sent = null);
      if (e is ApiError && e.code.endsWith('VERIFICATION_REQUIRED')) {
        // Progressive verification: the first contact action is where we ask, and the signal isn't spent.
        final verified = await context.push<bool>('/verify');
        if (verified == true && mounted) _signal();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t send. Your signal wasn\'t used.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final padding = MediaQuery.paddingOf(context);
    final c = context.od;
    return Stack(
      fit: StackFit.expand,
      children: [
        OdMedia(seed: m.seed, url: m.previewUrl),
        const OdScrim(),
        Positioned(
          top: padding.top + OdSpace.x1,
          left: OdSpace.gutter,
          right: OdSpace.gutter,
          child: Row(
            children: [
              Text(
                'Nearby',
                style: context.type.titleLarge?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Flexible(
                child: Consumer(
                  builder: (context, ref, _) {
                    final budget = ref.watch(signalsLeftProvider).value;
                    final label = budget == null
                        ? 'Signals'
                        : budget.remaining > 0
                        ? '${budget.remaining} ${budget.remaining == 1 ? 'signal' : 'signals'} left today'
                        : budget.nextFreesAt == null
                        ? 'No signals left today'
                        : 'More at ${TimeOfDay.fromDateTime(budget.nextFreesAt!.toLocal()).format(context)}';
                    return OdFrosted(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OdSpace.x1_5,
                        vertical: OdSpace.x1,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.labelMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: OdSpace.gutter,
          right: OdSpace.gutter,
          bottom: padding.bottom + 104,
          // With very large text the action stacks under the details instead of squeezing beside them.
          child: Builder(
            builder: (context) {
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.prompt != null) ...[
                    OdFrosted(
                      radius: OdRadius.md,
                      padding: const EdgeInsets.symmetric(
                        horizontal: OdSpace.x1_5,
                        vertical: OdSpace.x1,
                      ),
                      child: Text(
                        'Today\'s prompt · ${m.prompt}',
                        style: context.type.labelMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: OdSpace.x1),
                  ],
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.headlineSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: OdSpace.x1),
                      if (m.liveCapture) const OdLiveBadge(),
                    ],
                  ),
                  const SizedBox(height: OdSpace.x0_5),
                  Text(
                    [
                      m.activity,
                      m.distance,
                      if (m.postedAgo != null) m.postedAgo,
                    ].where((p) => p != null && p.isNotEmpty).join(' · '),
                    style: context.type.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              );
              final action = AnimatedSwitcher(
                duration: OdMotion.of(context, OdMotion.standard),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: _sent == null
                    ? OdButton(
                        key: const ValueKey('send'),
                        label: 'Signal',
                        icon: Icons.waving_hand_rounded,
                        onPressed: _signal,
                      )
                    : Container(
                        key: const ValueKey('sent'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: OdSpace.x2,
                          vertical: OdSpace.x1_5,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceRaised.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(OdRadius.pill),
                        ),
                        child: Text(
                          '${_sent!.emoji} Sent',
                          style: context.type.labelLarge,
                        ),
                      ),
              );
              return MediaQuery.textScalerOf(context).scale(16) > 24
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        details,
                        const SizedBox(height: OdSpace.x1_5),
                        action,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: details),
                        action,
                      ],
                    );
            },
          ),
        ),
        Positioned(
          right: OdSpace.x1,
          top: 0,
          bottom: 0,
          child: Center(
            child: _PageDots(index: widget.index, total: widget.total + 1),
          ),
        ),
      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send ${moment.firstName} a signal',
          style: context.type.titleLarge,
        ),
        const SizedBox(height: OdSpace.x0_5),
        Text(
          left > 0
              ? 'They\'ll see your reaction and first name. If they reveal too, you can chat. $left left today.'
              : 'You\'ve used today\'s signals. They refresh tomorrow, so the ones you send matter.',
          style: context.type.bodyMedium,
        ),
        const SizedBox(height: OdSpace.x2),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: OdSpace.x1,
          crossAxisSpacing: OdSpace.x1,
          childAspectRatio: 2.6,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final r in SignalReaction.values)
              OdPressable(
                onTap: left > 0 ? () => Navigator.of(context).pop(r) : null,
                semanticLabel: r.label,
                child: OdCard(
                  padding: const EdgeInsets.symmetric(horizontal: OdSpace.x1_5),
                  child: Row(
                    children: [
                      Text(r.emoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: OdSpace.x1),
                      Expanded(
                        child: Text(r.label, style: context.type.labelLarge),
                      ),
                    ],
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
    return ColoredBox(
      color: context.od.canvas,
      child: const Center(
        child: OdClosureCard(
          title: 'That\'s everyone nearby for now',
          message: 'New moments appear as people share them. Meanwhile, maybe go make one of your own.',
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: OdMotion.of(context, OdMotion.quick),
            margin: const EdgeInsets.symmetric(vertical: 3),
            width: 4,
            height: i == index ? 18 : 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == index ? 0.95 : 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class _NearbyLoading extends StatelessWidget {
  const _NearbyLoading();

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OdSpace.gutter,
        padding.top + OdSpace.x2,
        OdSpace.gutter,
        padding.bottom + 110,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OdSkeleton(width: 96, height: 24),
          Spacer(),
          OdSkeleton(width: 160, height: 26),
          SizedBox(height: OdSpace.x1),
          OdSkeleton(width: 220, height: 16),
        ],
      ),
    );
  }
}
