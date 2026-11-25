import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/relays.dart';
import '../../core/repositories.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => switch (e) {
  LocationRequired() =>
    'Answers are shared nearby, so share your area on Nearby first.',
  ApiError(:final detail) => detail,
  _ => 'Couldn\'t reach OneDay. Check your connection and try again.',
};

/// A Story Relay: a public story and the stories that answered it, in order. Anyone who can see it can add their
/// own answer (in words for now); the story's owner can ask to spotlight up to three answers.
class RelayScreen extends ConsumerStatefulWidget {
  const RelayScreen({super.key, required this.momentId});

  /// Any story in the relay.
  final String momentId;

  @override
  ConsumerState<RelayScreen> createState() => _RelayScreenState();
}

class _RelayScreenState extends ConsumerState<RelayScreen> {
  final _answer = TextEditingController();
  Relay? _relay;
  String? _loadError;
  bool _busy = false;

  RelayRepository get _repo => ref.read(relayRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final relay = await _repo.relay(widget.momentId);
      if (mounted) {
        setState(() {
          _relay = relay;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send(Relay relay) async {
    final text = _answer.text.trim();
    final last = relay.links.isEmpty ? null : relay.links.last;
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      // An answer continues the relay from its latest story.
      await _repo.answer(last?.momentId ?? widget.momentId, text);
      _answer.clear();
      ref.invalidate(friendsStoriesProvider);
      await _load();
      if (mounted) _say('Added to the relay. It disappears in 24 hours.');
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _spotlight(Relay relay, RelayLink link) async {
    final root = relay.root;
    if (root == null) return;
    setState(() => _busy = true);
    try {
      await _repo.proposeSpotlight(root.momentId, link.momentId);
      if (mounted) {
        _say('Asked ${link.firstName}. It\'s spotlit if they agree.');
      }
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final relay = _relay;
    final ownsRoot = relay?.root?.mine ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(relay?.activity == null ? 'Relay' : 'Relay · ${relay!.activity}')),
      body: relay == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator.adaptive()
                  : Padding(
                      padding: const EdgeInsets.all(OdSpace.x3),
                      child: Text(_loadError!, textAlign: TextAlign.center),
                    ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(OdSpace.gutter),
                    children: [
                      Text(
                        'Stories that answered one another today. Everyone here sees only first names.',
                        style: context.type.bodyMedium,
                      ),
                      const SizedBox(height: OdSpace.x2),
                      for (final link in relay.links)
                        Padding(
                          padding: const EdgeInsets.only(bottom: OdSpace.x1_5),
                          child: OdCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(OdRadius.sm),
                                child: SizedBox.square(
                                  dimension: 48,
                                  child: OdMedia(
                                    url: link.previewUrl,
                                    seed: link.momentId.hashCode,
                                    activity: link.activity,
                                  ),
                                ),
                              ),
                              title: Text(
                                link.mine ? 'You' : link.firstName,
                              ),
                              subtitle: Text(
                                [
                                  if (link.position == 0) 'Started it',
                                  if (link.activity != null) link.activity!,
                                  if (link.spotlit) 'Spotlit',
                                ].join(' · '),
                              ),
                              trailing:
                                  ownsRoot &&
                                      !link.mine &&
                                      !link.spotlit &&
                                      link.position > 0
                                  ? TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _spotlight(relay, link),
                                      child: const Text('Spotlight'),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      if (!relay.open)
                        Text(
                          'This relay is full. Start your own with a new story.',
                          style: context.type.bodyMedium,
                        ),
                    ],
                  ),
                ),
                if (relay.open)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(
                      OdSpace.gutter,
                      OdSpace.x1,
                      OdSpace.gutter,
                      OdSpace.x1_5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _answer,
                            enabled: !_busy,
                            maxLength: 200,
                            minLines: 1,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Answer with your own',
                              counterText: '',
                            ),
                            onSubmitted: (_) => _send(relay),
                          ),
                        ),
                        const SizedBox(width: OdSpace.x1),
                        OdIconButton(
                          icon: Icons.arrow_upward_rounded,
                          semanticLabel: 'Add to the relay',
                          onPressed: _busy ? null : () => _send(relay),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Requests to spotlight your answers: accepting puts your answer at the front of that story's relay.
class SpotlightRequestsCard extends ConsumerStatefulWidget {
  const SpotlightRequestsCard({super.key});

  @override
  ConsumerState<SpotlightRequestsCard> createState() =>
      _SpotlightRequestsCardState();
}

class _SpotlightRequestsCardState extends ConsumerState<SpotlightRequestsCard> {
  List<SpotlightRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await ref.read(relayRepositoryProvider).spotlightRequests();
      if (mounted) setState(() => _requests = requests);
    } catch (_) {
      // Quietly absent: this card is a nicety, not a screen of its own.
    }
  }

  Future<void> _decide(SpotlightRequest request, bool accept) async {
    try {
      await ref
          .read(relayRepositoryProvider)
          .decideSpotlight(request.id, accept: accept);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_problem(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_requests.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: OdSpace.x3),
      child: OdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spotlight requests', style: context.type.titleMedium),
            for (final request in _requests)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${request.withFirstName} wants to spotlight your answer'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _decide(request, false),
                      child: const Text('No thanks'),
                    ),
                    TextButton(
                      onPressed: () => _decide(request, true),
                      child: const Text('Yes'),
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
