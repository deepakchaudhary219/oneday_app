import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';
import '../signals/signals_screen.dart';
import '../stories/story_viewer.dart';
import 'chat_thread_screen.dart';

/// Conversations, with friends' stories on top (Instagram's rings) and the Signals digest one tap away.
/// No unread counters as badges of guilt, only a quiet dot; warmth glows instead of streak numbers.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final stories = ref.watch(friendsStoriesProvider);
    final signals = ref.watch(pendingSignalsProvider);
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
              title: const Text('Chats'),
              actions: [
                OdIconButton(
                  icon: Icons.edit_square,
                  semanticLabel: 'New chat',
                  onPressed: () {},
                ),
                const SizedBox(width: OdSpace.x1),
              ],
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                // Ring + label, growing with the text size so large text never clips.
                height: 86 + MediaQuery.textScalerOf(context).scale(13) * 1.4,
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
                          child: OdSkeleton(width: 64, height: 64, radius: 32),
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
                        const SizedBox(width: OdSpace.x2),
                    itemBuilder: (context, i) => OdPressable(
                      onTap: () => openStory(context, list, i),
                      semanticLabel: '${list[i].firstName}\'s story',
                      child: Column(
                        children: [
                          OdAvatar(
                            name: list[i].firstName,
                            size: 62,
                            ring: list[i].mine ? OdRing.seen : OdRing.live,
                            seed: list[i].seed,
                          ),
                          const SizedBox(height: OdSpace.x0_5),
                          SizedBox(
                            width: 72,
                            child: Text(
                              list[i].mine ? 'Your story' : list[i].firstName,
                              style: context.type.labelMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: signals.maybeWhen(
                data: (list) => list.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(
                          OdSpace.gutter,
                          0,
                          OdSpace.gutter,
                          OdSpace.x1_5,
                        ),
                        child: OdPressable(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SignalsScreen(),
                            ),
                          ),
                          semanticLabel: 'Open signals',
                          child: OdCard(
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: context.od.brandGradient,
                                  ),
                                  child: const Icon(
                                    Icons.waving_hand_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: OdSpace.x1_5),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        list.length == 1
                                            ? '1 person reached out'
                                            : '${list.length} people reached out',
                                        style: context.type.titleMedium,
                                      ),
                                      Text(
                                        'Take your time: signals wait 48 hours',
                                        style: context.type.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: context.od.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
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
              data: (list) => SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) =>
                    _ConversationTile(conversation: list[i]),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
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
          vertical: OdSpace.x1,
        ),
        child: Row(
          children: [
            OdWarmthGlow(
              level: conv.warmth,
              child: OdAvatar(
                name: conv.firstName,
                size: 52,
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
                          overflow: TextOverflow.ellipsis,
                          style: context.type.titleMedium,
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
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conv.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodyMedium?.copyWith(
                      color: conv.unread ? c.textPrimary : c.textSecondary,
                      fontWeight: conv.unread
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: OdSpace.x1),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  conv.lastAt == null
                      ? 'New'
                      : ago(DateTime.now().difference(conv.lastAt!)),
                  style: context.type.labelSmall,
                ),
                const SizedBox(height: 6),
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
              ],
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
      padding: EdgeInsets.symmetric(
        horizontal: OdSpace.gutter,
        vertical: OdSpace.x1,
      ),
      child: Row(
        children: [
          OdSkeleton(width: 52, height: 52, radius: 26),
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
