import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// Every design-system component in its states: for design review, and the place to check a change.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _loading = false;
  bool _chip = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Design system')),
      body: ListView(
        padding: const EdgeInsets.all(OdSpace.gutter),
        children: [
          _label(context, 'Buttons'),
          OdButton(
            label: 'Primary action',
            expand: true,
            loading: _loading,
            onPressed: () => setState(() => _loading = !_loading),
          ),
          const SizedBox(height: OdSpace.x1),
          Row(
            children: [
              Expanded(
                child: OdButton(
                  label: 'Secondary',
                  variant: OdButtonVariant.secondary,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: OdSpace.x1),
              Expanded(
                child: OdButton(
                  label: 'Block',
                  variant: OdButtonVariant.danger,
                  onPressed: () {},
                ),
              ),
            ],
          ),
          OdButton(
            label: 'Ghost',
            variant: OdButtonVariant.ghost,
            onPressed: () {},
          ),
          const OdButton(label: 'Disabled', onPressed: null),
          _label(context, 'Avatars and rings'),
          const Row(
            children: [
              OdAvatar(name: 'Riya', ring: OdRing.live, seed: 1),
              SizedBox(width: OdSpace.x2),
              OdAvatar(name: 'Arjun', ring: OdRing.seen, seed: 2),
              SizedBox(width: OdSpace.x2),
              OdWarmthGlow(level: 3, child: OdAvatar(name: 'Sana', seed: 3)),
            ],
          ),
          _label(context, 'Chips and badges'),
          Wrap(
            spacing: OdSpace.x1,
            runSpacing: OdSpace.x1,
            children: [
              OdChip(
                label: 'Trek',
                selected: _chip,
                onTap: () => setState(() => _chip = !_chip),
              ),
              const OdChip(label: 'Chess', icon: Icons.extension_rounded),
              const OdLiveBadge(),
              const OdTimePill(text: '1 day left'),
            ],
          ),
          _label(context, 'Loading'),
          const OdSkeleton(height: 18),
          const SizedBox(height: OdSpace.x1),
          const OdSkeleton(width: 180, height: 14),
          _label(context, 'Over media'),
          SizedBox(
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OdRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const OdMediaArt(seed: 3),
                  const OdScrim(),
                  Center(
                    child: OdFrosted(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OdSpace.x2,
                        vertical: OdSpace.x1,
                      ),
                      child: Text(
                        'Frosted chrome',
                        style: context.type.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _label(context, 'Closure'),
          const OdCard(
            child: OdClosureCard(
              title: 'All caught up',
              message: 'A stopping cue, not a dead end.',
            ),
          ),
          _label(context, 'Sheet'),
          OdButton(
            label: 'Open sheet',
            variant: OdButtonVariant.secondary,
            onPressed: () => showOdSheet<void>(
              context,
              builder: (context) => Text(
                'Sheets keep the house style.',
                style: context.type.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: OdSpace.x6),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: OdSpace.x3, bottom: OdSpace.x1),
    child: Text(text.toUpperCase(), style: context.type.labelSmall),
  );
}
