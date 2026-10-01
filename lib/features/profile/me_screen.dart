import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../gallery/gallery_screen.dart';

/// You: your story, your Pulse Status, and the controls that matter (privacy, safety). There are no follower
/// counts and no score, because there's nothing to compare.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  static const _moods = [
    ('😌', 'Chill'),
    ('🥳', 'Celebrating'),
    ('🧗', 'Up for adventure'),
    ('🎧', 'Heads down'),
    ('🫂', 'Social'),
  ];
  int? _mood;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(pinned: true, title: Text('Me')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: OdSpace.gutter),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    const OdAvatar(
                      name: 'Asha',
                      size: 84,
                      ring: OdRing.live,
                      seed: 9,
                    ),
                    const SizedBox(width: OdSpace.x2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Asha', style: context.type.headlineSmall),
                          const SizedBox(height: 2),
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
                                  'Verified · Bengaluru',
                                  overflow: TextOverflow.ellipsis,
                                  style: context.type.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OdSpace.x3),
                Text('Pulse Status', style: context.type.titleMedium),
                const SizedBox(height: OdSpace.x0_5),
                Text(
                  'Friends only · gone in 24 hours',
                  style: context.type.bodyMedium,
                ),
                const SizedBox(height: OdSpace.x1_5),
                Wrap(
                  spacing: OdSpace.x1,
                  runSpacing: OdSpace.x1,
                  children: [
                    for (var i = 0; i < _moods.length; i++)
                      OdChip(
                        label: '${_moods[i].$1}  ${_moods[i].$2}',
                        selected: _mood == i,
                        onTap: () =>
                            setState(() => _mood = _mood == i ? null : i),
                      ),
                  ],
                ),
                const SizedBox(height: OdSpace.x3),
                const _Section(
                  title: 'You',
                  items: [
                    (
                      Icons.auto_stories_rounded,
                      'Memory Trail',
                      'Your kept stories, only for you',
                    ),
                    (
                      Icons.hourglass_bottom_rounded,
                      'Time Capsules',
                      'Messages waiting for their day',
                    ),
                    (Icons.favorite_border_rounded, 'Dating Lens', 'Off'),
                  ],
                ),
                const _Section(
                  title: 'Privacy & safety',
                  items: [
                    (
                      Icons.privacy_tip_rounded,
                      'Privacy controls',
                      'What you share, and switching it off',
                    ),
                    (
                      Icons.location_off_rounded,
                      'Safe Zones',
                      'Places where you\'re never shown',
                    ),
                    (
                      Icons.shield_rounded,
                      'Trusted contact',
                      'For Date Mode check-ins',
                    ),
                    (Icons.block_rounded, 'Blocked people', ''),
                  ],
                ),
                _Section(
                  title: 'More',
                  items: const [
                    (
                      Icons.workspace_premium_rounded,
                      'OneDay Plus',
                      'Wider radius, more plans. Safety is never paid.',
                    ),
                    (Icons.help_outline_rounded, 'Help & grievances', ''),
                  ],
                  trailing: OdButton(
                    label: 'Design system gallery',
                    variant: OdButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GalleryScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items, this.trailing});

  final String title;
  final List<(IconData, String, String)> items;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return Padding(
      padding: const EdgeInsets.only(bottom: OdSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.type.labelMedium),
          const SizedBox(height: OdSpace.x1),
          OdCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (icon, label, detail) in items)
                  ListTile(
                    leading: Icon(icon, color: c.textSecondary),
                    title: Text(label, style: context.type.titleMedium),
                    subtitle: detail.isEmpty
                        ? null
                        : Text(detail, style: context.type.bodyMedium),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: c.textTertiary,
                    ),
                    onTap: () {},
                  ),
              ],
            ),
          ),
          if (trailing != null) Center(child: trailing),
        ],
      ),
    );
  }
}
