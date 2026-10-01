import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';
import '../gallery/gallery_screen.dart';

/// You, laid out like the profiles people know (Instagram's header, highlights and grid) with OneDay's rules:
/// no follower counts and no likes, because there's nothing to compare. The grid is your Memory Trail, kept
/// moments only you can see. Settings live behind the menu, one tap away.
class MeScreen extends ConsumerStatefulWidget {
  const MeScreen({super.key});

  @override
  ConsumerState<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends ConsumerState<MeScreen> {
  static const _moods = [
    ('😌', 'Chill'),
    ('🥳', 'Celebrating'),
    ('🧗', 'Up for adventure'),
    ('🎧', 'Heads down'),
    ('🫂', 'Social'),
  ];
  static const _highlights = [
    ('Treks', 'trek', 31),
    ('Food', 'street food', 32),
    ('Monsoon', 'monsoon', 33),
    ('Gigs', 'gig', 34),
    ('Goa', 'beach', 35),
  ];
  int? _mood;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    // The token knows the moment a face check passes; the profile catches up on the next fetch.
    ref.listen(
      authControllerProvider,
      (_, _) => ref.invalidate(myProfileProvider),
    );
    final profile = ref.watch(myProfileProvider).value;
    final name = profile?.displayName ?? '';
    final verified =
        ref.watch(authControllerProvider).verified ||
        (profile?.verified ?? false);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            titleSpacing: OdSpace.gutter,
            title: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: c.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name.isEmpty ? 'Me' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.headlineSmall,
                  ),
                ),
              ],
            ),
            actions: [
              OdIconButton(
                icon: Icons.add_box_outlined,
                semanticLabel: 'New moment',
                onPressed: () {},
              ),
              const SizedBox(width: OdSpace.x0_5),
              OdIconButton(
                icon: Icons.menu_rounded,
                semanticLabel: 'Settings',
                onPressed: () => _settings(context),
              ),
              const SizedBox(width: OdSpace.x1),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: OdSpace.gutter),
            sliver: SliverList.list(
              children: [
                const SizedBox(height: OdSpace.x1),
                Row(
                  children: [
                    OdAvatar(
                      name: name.isEmpty ? '?' : name,
                      size: 92,
                      ring: OdRing.live,
                      seed: 2,
                    ),
                    const SizedBox(width: OdSpace.x2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name.isEmpty
                              ? const OdSkeleton(width: 120, height: 24)
                              : Text(name, style: context.type.headlineSmall),
                          if (profile?.homeRegion != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 15,
                                  color: c.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    profile!.homeRegion!,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.type.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: OdSpace.x1),
                          if (verified)
                            Row(
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 16,
                                  color: c.safety,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Verified',
                                    overflow: TextOverflow.ellipsis,
                                    style: context.type.labelLarge?.copyWith(
                                      color: c.safety,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: OdChip(
                                label: 'Get verified',
                                icon: Icons.verified_outlined,
                                onTap: () => context.push('/verify'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (profile?.bio != null) ...[
                  const SizedBox(height: OdSpace.x1_5),
                  Text(profile!.bio!, style: context.type.bodyLarge),
                ],
                const SizedBox(height: OdSpace.x2),
                Row(
                  children: [
                    Expanded(
                      child: OdButton(
                        label: 'Edit profile',
                        variant: OdButtonVariant.secondary,
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: OdSpace.x1),
                    Expanded(
                      child: OdButton(
                        label: 'Share profile',
                        variant: OdButtonVariant.secondary,
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OdSpace.x3),
                Text.rich(
                  TextSpan(
                    text: 'Pulse Status',
                    style: context.type.titleMedium,
                    children: [
                      TextSpan(
                        text: '  · friends only · 24 h',
                        style: context.type.bodyMedium?.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OdSpace.x1),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.textScalerOf(context).scale(14) + 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: OdSpace.gutter),
                itemCount: _moods.length,
                separatorBuilder: (_, _) => const SizedBox(width: OdSpace.x1),
                itemBuilder: (context, i) => Center(
                  child: OdChip(
                    label: '${_moods[i].$1}  ${_moods[i].$2}',
                    selected: _mood == i,
                    onTap: () => setState(() => _mood = _mood == i ? null : i),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 96 + MediaQuery.textScalerOf(context).scale(12) * 1.4,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  OdSpace.gutter,
                  OdSpace.x2,
                  OdSpace.gutter,
                  0,
                ),
                itemCount: _highlights.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: OdSpace.x2),
                itemBuilder: (context, i) => i == 0
                    ? const _Highlight(label: 'New')
                    : _Highlight(
                        label: _highlights[i - 1].$1,
                        activity: _highlights[i - 1].$2,
                        seed: _highlights[i - 1].$3,
                      ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _Tabs(
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          if (_tab == 0)
            SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 0.8,
              ),
              itemCount: 9,
              itemBuilder: (context, i) => _MemoryTile(index: i),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(OdSpace.gutter),
              sliver: SliverList.list(
                children: const [
                  _CapsuleCard(
                    to: 'Riya',
                    opens: 'Opens 12 Nov',
                    note: 'For your birthday trek',
                  ),
                  SizedBox(height: OdSpace.x1),
                  _CapsuleCard(
                    to: 'Future me',
                    opens: 'Opens 1 Jan',
                    note: 'What I hoped 2027 would be',
                  ),
                ],
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  void _settings(BuildContext context) => showOdSheet<void>(
    context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settings', style: sheet.type.titleLarge),
        const SizedBox(height: OdSpace.x1),
        for (final (icon, label) in const [
          (Icons.privacy_tip_outlined, 'Privacy controls'),
          (Icons.location_off_outlined, 'Safe Zones'),
          (Icons.shield_outlined, 'Trusted contact'),
          (Icons.favorite_border_rounded, 'Dating Lens'),
          (Icons.block_rounded, 'Blocked people'),
          (Icons.workspace_premium_outlined, 'OneDay Plus'),
          (Icons.help_outline_rounded, 'Help & grievances'),
        ])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: sheet.od.textSecondary),
            title: Text(label, style: sheet.type.titleMedium),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: sheet.od.textTertiary,
            ),
            onTap: () {},
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.palette_outlined, color: sheet.od.textSecondary),
          title: Text('Design system gallery', style: sheet.type.titleMedium),
          onTap: () {
            Navigator.of(sheet).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GalleryScreen()),
            );
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout_rounded, color: sheet.od.danger),
          title: Text(
            'Sign out',
            style: sheet.type.titleMedium?.copyWith(color: sheet.od.danger),
          ),
          onTap: () {
            Navigator.of(sheet).pop();
            ref.read(authControllerProvider.notifier).signOut();
          },
        ),
      ],
    ),
  );
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.label, this.activity, this.seed});

  final String label;
  final String? activity;
  final int? seed;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return OdPressable(
      onTap: () {},
      semanticLabel: activity == null ? 'New highlight' : '$label highlight',
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            Container(
              width: 66,
              height: 66,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.outline, width: 1.5),
              ),
              child: ClipOval(
                child: activity == null
                    ? ColoredBox(
                        color: c.surfaceRaised,
                        child: Icon(
                          Icons.add_rounded,
                          color: c.textPrimary,
                          size: 28,
                        ),
                      )
                    : OdMediaArt(seed: seed!, activity: activity),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.labelMedium?.copyWith(color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    const tabs = [
      (Icons.grid_on_rounded, 'Memory Trail'),
      (Icons.hourglass_bottom_rounded, 'Time Capsules'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: OdSpace.x2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.outline)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: OdPressable(
                  onTap: () => onChanged(i),
                  haptic: OdHaptic.selection,
                  semanticLabel: tabs[i].$2,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: i == index
                              ? c.textPrimary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Icon(
                      tabs[i].$1,
                      color: i == index ? c.textPrimary : c.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A kept moment: private to you, so the badge is a lock, never a like count.
class _MemoryTile extends StatelessWidget {
  const _MemoryTile({required this.index});

  final int index;

  static const _activities = [
    'trek',
    'chai at a café',
    'beach',
    'monsoon',
    'gig',
    'park',
    'city night',
    'sunrise',
    'brunch',
  ];
  static const _when = [
    '2d',
    '5d',
    '1w',
    '2w',
    '3w',
    '1mo',
    '1mo',
    '2mo',
    '3mo',
  ];

  @override
  Widget build(BuildContext context) {
    return OdPressable(
      onTap: () {},
      pressedScale: 0.97,
      semanticLabel: 'Memory from ${_when[index]} ago, ${_activities[index]}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          OdMediaArt(seed: 40 + index, activity: _activities[index]),
          const Positioned(
            top: 6,
            right: 6,
            child: Icon(Icons.lock_rounded, size: 14, color: Colors.white70),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Text(
              _when[index],
              style: context.type.labelSmall?.copyWith(
                color: Colors.white,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapsuleCard extends StatelessWidget {
  const _CapsuleCard({
    required this.to,
    required this.opens,
    required this.note,
  });

  final String to;
  final String opens;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return OdCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: c.brandGradient,
            ),
            child: const Icon(Icons.hourglass_top_rounded, color: Colors.white),
          ),
          const SizedBox(width: OdSpace.x1_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To $to', style: context.type.titleMedium),
                Text(note, style: context.type.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: OdSpace.x1),
          OdTimePill(text: opens),
        ],
      ),
    );
  }
}
