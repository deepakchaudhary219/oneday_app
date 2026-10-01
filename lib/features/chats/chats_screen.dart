import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';
import '../signals/signals_screen.dart';
import '../stories/story_viewer.dart';
import 'chat_thread_screen.dart';

/// Conversations, in the shape people know from Instagram and Snapchat: stories on top, a search field, then
/// rows with a quick-reply camera. What we leave out on purpose: streak counters, read-receipt anxiety, and
/// unread badges as guilt (a quiet dot instead). Warmth glows around people you're close to.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

enum _Filter { all, unread }

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final stories = ref.watch(friendsStoriesProvider);
    final signals = ref.watch(pendingSignalsProvider);
    final c = context.od;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(conversationsProvider);
          ref.invalidate(friendsStoriesProvider);
          ref.invalidate(pendingSignalsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              titleSpacing: OdSpace.gutter,
              title: Row(
                children: [
                  const OdAvatar(name: 'You', seed: 2, size: 34),
                  const SizedBox(width: OdSpace.x1_5),
                  Flexible(
                    child: Text(
                      'Chats',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.headlineSmall,
                    ),
                  ),
                ],
              ),
              actions: [
                OdIconButton(
                  icon: Icons.person_add_alt_1_rounded,
                  semanticLabel: 'Add friends',
                  onPressed: () {},
                ),
                const SizedBox(width: OdSpace.x0_5),
                OdIconButton(
                  icon: Icons.edit_square,
                  semanticLabel: 'New chat',
                  onPressed: () {},
                ),
                const SizedBox(width: OdSpace.x1),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  OdSpace.gutter,
                  OdSpace.x0_5,
                  OdSpace.gutter,
                  OdSpace.x1_5,
                ),
                child: _SearchField(
                  onChanged: (q) =>
                      setState(() => _query = q.trim().toLowerCase()),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                // Ring + label, growing with the text size so large text never clips.
                height: 92 + MediaQuery.textScalerOf(context).scale(13) * 1.4,
                child: stories.when(
                  loading: () => ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: OdSpace.gutter,
                    ),
                    children: [
                      for (var i = 0; i < 5; i++)
                        const Padding(
                          padding: EdgeInsets.only(right: OdSpace.x2),
                          child: OdSkeleton(width: 68, height: 68, radius: 34),
                        ),
                    ],
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) => ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: OdSpace.gutter,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: OdSpace.x1_5),
                    itemBuilder: (context, i) => _StoryBubble(
                      story: list[i],
                      onTap: () => openStory(context, list, i),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: signals.maybeWhen(
                data: (list) => list.isEmpty
                    ? const SizedBox.shrink()
                    : _SignalsCard(signals: list),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  OdSpace.gutter,
                  OdSpace.x1,
                  OdSpace.gutter,
                  OdSpace.x1,
                ),
                child: Wrap(
                  runSpacing: OdSpace.x1,
                  children: [
                    for (final f in _Filter.values) ...[
                      OdChip(
                        label: f == _Filter.all ? 'All' : 'Unread',
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                      const SizedBox(width: OdSpace.x1),
                    ],
                  ],
                ),
              ),
            ),
            conversations.when(
              loading: () => SliverList.builder(
                itemCount: 6,
                itemBuilder: (_, _) => const _TileSkeleton(),
              ),
              error: (_, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: OdClosureCard(
                  icon: Icons.wifi_off_rounded,
                  title: 'Couldn\'t load chats',
                  message: 'Check your connection.',
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(conversationsProvider),
                ),
              ),
              data: (all) {
                final list = all
                    .where(
                      (x) =>
                          _query.isEmpty ||
                          x.firstName.toLowerCase().contains(_query),
                    )
                    .where((x) => _filter == _Filter.all || x.unread)
                    .toList();
                if (list.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(OdSpace.x4),
                      child: Text(
                        _query.isEmpty
                            ? 'You\'re all caught up.'
                            : 'No one called "$_query" yet.',
                        textAlign: TextAlign.center,
                        style: context.type.bodyMedium?.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  );
                }
                return SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _ConversationTile(conversation: list[i]),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: context.type.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search',
        prefixIcon: Icon(Icons.search_rounded, color: c.textTertiary),
        filled: true,
        fillColor: c.surfaceRaised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OdRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OdRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    return OdPressable(
      onTap: onTap,
      semanticLabel: story.mine ? 'Your story' : '${story.firstName}\'s story',
      child: SizedBox(
        width: 74,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                OdAvatar(
                  name: story.firstName,
                  size: 66,
                  ring: story.mine ? OdRing.seen : OdRing.live,
                  seed: story.seed,
                ),
                if (story.mine)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: c.brandGradient,
                        border: Border.all(color: c.canvas, width: 2.5),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              story.mine ? 'Your story' : story.firstName,
              style: context.type.labelMedium?.copyWith(color: c.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Signals digest entry: overlapping faces say "people" before the words do.
class _SignalsCard extends StatelessWidget {
  const _SignalsCard({required this.signals});

  final List<IncomingSignal> signals;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final faces = signals.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OdSpace.gutter,
        OdSpace.x1,
        OdSpace.gutter,
        OdSpace.x1,
      ),
      child: OdPressable(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SignalsScreen())),
        semanticLabel: 'Open signals',
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            gradient: c.brandGradient,
            borderRadius: BorderRadius.circular(OdRadius.lg),
          ),
          child: Container(
            padding: const EdgeInsets.all(OdSpace.x1_5),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(OdRadius.lg - 1.5),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44 + (faces.length - 1) * 22,
                  height: 44,
                  child: Stack(
                    children: [
                      for (var i = 0; i < faces.length; i++)
                        Positioned(
                          left: i * 22.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: c.surface, width: 2.5),
                            ),
                            child: OdAvatar(
                              name: faces[i].firstName,
                              seed: faces[i].seed,
                              size: 39,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: OdSpace.x1_5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signals.length == 1
                            ? '1 person reached out'
                            : '${signals.length} people reached out',
                        style: context.type.titleMedium,
                      ),
                      Text(
                        'Take your time: signals wait 48 hours',
                        style: context.type.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final conv = conversation;
    final fresh = conv.lastAt == null;
    final when = fresh ? null : ago(DateTime.now().difference(conv.lastAt!));
    return OdPressable(
      pressedScale: 0.98,
      haptic: OdHaptic.selection,
      semanticLabel: 'Chat with ${conv.firstName}',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatThreadScreen(conversation: conv),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OdSpace.gutter,
          vertical: 10,
        ),
        child: Row(
          children: [
            OdWarmthGlow(
              level: conv.warmth,
              child: OdAvatar(
                name: conv.firstName,
                size: 56,
                ring: conv.hasStory ? OdRing.live : OdRing.none,
                seed: conv.seed,
              ),
            ),
            const SizedBox(width: OdSpace.x1_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          conv.firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.titleMedium?.copyWith(
                            fontWeight: conv.unread
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (conv.encrypted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: c.textTertiary,
                        ),
                      ],
                      if (conv.warmth >= 3) ...[
                        const SizedBox(width: 4),
                        Text('✨', style: context.type.labelMedium),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (fresh) ...[
                        Icon(
                          Icons.waving_hand_rounded,
                          size: 14,
                          color: c.brand,
                        ),
                        const SizedBox(width: 4),
                      ] else if (conv.lastFromMe) ...[
                        Icon(
                          Icons.near_me_outlined,
                          size: 14,
                          color: c.textTertiary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: fresh
                                ? 'New connection · ${conv.preview}'
                                : conv.preview,
                            children: [
                              if (when != null)
                                TextSpan(
                                  text: ' · $when',
                                  style: TextStyle(
                                    color: c.textTertiary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.bodyMedium?.copyWith(
                            color: conv.unread || fresh
                                ? c.textPrimary
                                : c.textSecondary,
                            fontWeight: conv.unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: OdSpace.x1),
            AnimatedOpacity(
              opacity: conv.unread ? 1 : 0,
              duration: OdMotion.of(context, OdMotion.quick),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c.brand,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: OdSpace.x1),
            OdIconButton(
              icon: Icons.photo_camera_outlined,
              semanticLabel: 'Reply to ${conv.firstName} with a photo',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: OdSpace.gutter, vertical: 10),
      child: Row(
        children: [
          OdSkeleton(width: 56, height: 56, radius: 28),
          SizedBox(width: OdSpace.x1_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OdSkeleton(width: 120, height: 14),
                SizedBox(height: OdSpace.x1),
                OdSkeleton(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
