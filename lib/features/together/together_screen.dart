import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/prompts.dart';
import '../../core/providers.dart';
import '../../core/pulse_status.dart';
import '../../core/repositories.dart';
import '../../design_system/design_system.dart';
import '../amas/amas_screen.dart';
import '../capsules/capsules_screen.dart';
import '../dates/dates_screen.dart';
import '../figures/figures_screen.dart';
import '../live/live_screen.dart';
import '../plans/plans_screen.dart';
import '../relays/relay_screen.dart';
import '../right_now/right_now_screen.dart';
import '../threads/threads_screen.dart';

/// What's happening with people today: the day's prompt, how friends are doing, and the ways to meet up
/// (Plans and dates). Nothing here counts, ranks or streaks.
class TogetherScreen extends ConsumerWidget {
  const TogetherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.od;
    final statuses = ref.watch(friendStatusesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Together')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          OdSpace.gutter,
          OdSpace.x1,
          OdSpace.gutter,
          OdSpace.x6,
        ),
        children: [
          const SpotlightRequestsCard(),
          const _PromptCard(),
          const SizedBox(height: OdSpace.x3),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.groups_rounded, color: c.textSecondary),
            title: const Text('Plans nearby'),
            subtitle: const Text(
              'Small meet-ups at safe public places. The host approves who joins.',
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.favorite_border_rounded, color: c.textSecondary),
            title: const Text('Dates'),
            subtitle: const Text(
              'Plan one with a Connection, with check-ins and a trusted contact.',
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DatesScreen()),
            ),
          ),
          for (final (icon, title, subtitle, Widget screen) in [
            (
              Icons.bolt_rounded,
              'Right Now',
              'Up for something in the next hour? Say so, and see who else is.',
              const RightNowScreen(),
            ),
            (
              Icons.auto_stories_outlined,
              'Threads',
              'One shared story for a trip, a wedding or a festival week.',
              const ThreadsScreen(),
            ),
            (
              Icons.lock_clock_outlined,
              'Time Capsules',
              'Words sealed until a day you choose, for you or a friend.',
              const CapsulesScreen(),
            ),
            (
              Icons.verified_outlined,
              'Public figures',
              'Follow verified creators, artists and organisations.',
              const FiguresScreen(),
            ),
            (
              Icons.forum_outlined,
              'AMAs',
              'Ask a figure anything, live, with people from home.',
              const AmasScreen(),
            ),
            (
              Icons.videocam_outlined,
              'Circle Live',
              'Go live to your connections for up to an hour. Never recorded.',
              const LivesScreen(),
            ),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: c.textSecondary),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: c.textTertiary,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
            ),
          const SizedBox(height: OdSpace.x3),
          Text('How friends are doing', style: context.type.titleMedium),
          const SizedBox(height: OdSpace.x0_5),
          Text(
            'Friends only, gone in a day. Nobody sees who looked.',
            style: context.type.bodyMedium,
          ),
          const SizedBox(height: OdSpace.x1),
          ...switch (statuses) {
            AsyncData(:final value) when value.isEmpty => [
              Text(
                'No one has shared a status today.',
                style: context.type.bodyMedium,
              ),
            ],
            AsyncData(:final value) => [
              for (final status in value) _StatusTile(status: status),
            ],
            AsyncError() => [
              Text(
                'Couldn\'t load friends\' statuses.',
                style: context.type.bodyMedium,
              ),
            ],
            _ => const [
              Padding(
                padding: EdgeInsets.all(OdSpace.x2),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ],
          },
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status});

  final FriendStatus status;

  @override
  Widget build(BuildContext context) {
    final note = status.note;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(status.emoji, style: const TextStyle(fontSize: 28)),
      title: Text('${status.firstName} · ${status.moodLabel}'),
      subtitle: status.checkIn
          ? const Text('Might be a good moment to check in.')
          : (note == null || note.isEmpty ? null : Text(note)),
    );
  }
}

/// Today's Prompt: answer in a few words (a public story for a day) and the nearby answers open up.
class _PromptCard extends ConsumerStatefulWidget {
  const _PromptCard();

  @override
  ConsumerState<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends ConsumerState<_PromptCard> {
  final _answer = TextEditingController();
  bool _sending = false;
  String? _problem;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _send(TodaysPrompt prompt) async {
    final text = _answer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _problem = null;
    });
    try {
      await ref.read(promptRepositoryProvider).answer(prompt.promptKey, text);
      ref.invalidate(todaysPromptProvider);
      ref.invalidate(friendsStoriesProvider);
      if (mounted) _answer.clear();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _problem = switch (e) {
          LocationRequired() =>
            'Answers are shared nearby, so share your area on Nearby first.',
          ApiError(:final detail) => detail,
          _ => 'Couldn\'t send. Check your connection and try again.',
        },
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    final prompt = ref.watch(todaysPromptProvider).value;
    if (prompt == null || prompt.text.isEmpty) return const SizedBox.shrink();
    return OdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt.festival == null
                ? 'TODAY\'S PROMPT'
                : 'TODAY\'S PROMPT · ${prompt.festival!.toUpperCase()}',
            style: context.type.labelSmall?.copyWith(
              color: c.brand,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: OdSpace.x1),
          Text(prompt.text, style: context.type.titleLarge),
          const SizedBox(height: OdSpace.x1_5),
          if (!prompt.answeredByYou) ...[
            if (prompt.answeredNearby != null)
              Padding(
                padding: const EdgeInsets.only(bottom: OdSpace.x1),
                child: Text(
                  '${prompt.answeredNearby}. Answer to see what they said.',
                  style: context.type.bodyMedium,
                ),
              ),
            TextField(
              controller: _answer,
              enabled: !_sending,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Your answer',
                counterText: '',
              ),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: OdSpace.x1),
                child: Text(
                  _problem!,
                  style: context.type.bodyMedium?.copyWith(color: c.danger),
                ),
              ),
            const SizedBox(height: OdSpace.x1_5),
            OdButton(
              label: 'Answer nearby',
              expand: true,
              loading: _sending,
              onPressed: () => _send(prompt),
            ),
          ] else ...[
            Text(
              prompt.answers.isEmpty
                  ? (prompt.message ?? 'You answered. Nobody nearby has yet.')
                  : 'You answered. Nearby today:',
              style: context.type.bodyMedium,
            ),
            for (final answer in prompt.answers)
              Padding(
                padding: const EdgeInsets.only(top: OdSpace.x1),
                child: Text(
                  answer.activity == null
                      ? answer.firstName
                      : '${answer.firstName} · ${answer.activity}',
                  style: context.type.bodyLarge,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
