import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/repositories.dart';
import '../../core/right_now.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => switch (e) {
  LocationRequired() =>
    'Right Now works by distance, so share your area on Nearby first.',
  RightNowUnavailable() =>
    'Right Now isn\'t open in your city yet. It opens once enough people nearby use OneDay.',
  ApiError(:final detail) => detail,
  _ => 'Couldn\'t reach OneDay. Check your connection and try again.',
};

/// Right Now: "up for badminton for the next hour". You say what you're up for; people nearby who are up for
/// something can say "I'm in", and a chat opens only if you say yes (a no is silent). It ends on its own.
class RightNowScreen extends ConsumerStatefulWidget {
  const RightNowScreen({super.key});

  @override
  ConsumerState<RightNowScreen> createState() => _RightNowScreenState();
}

class _RightNowScreenState extends ConsumerState<RightNowScreen> {
  static const _lengths = [30, 60, 120];

  final _activity = TextEditingController();
  int _minutes = 60;
  MyRightNow? _mine;
  List<RightNowPerson> _people = const [];
  List<RightNowRequest> _requests = const [];
  String? _problemText;
  bool _loading = true;
  bool _busy = false;

  RightNowRepository get _repo => ref.read(rightNowRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _activity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final mine = await _repo.mine();
      final people = await _repo.nearby();
      final requests = mine == null
          ? const <RightNowRequest>[]
          : await _repo.requests();
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _people = people;
        _requests = requests;
        _problemText = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _problemText = _problem(e);
        _loading = false;
      });
    }
  }

  void _say(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _do(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _say(_problem(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final activity = _activity.text.trim();
    if (activity.isEmpty) return;
    await _do(() async {
      await _repo.start(activity, minutes: _minutes);
      _activity.clear();
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return Scaffold(
      appBar: AppBar(title: const Text('Right Now')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  OdSpace.gutter,
                  OdSpace.x1,
                  OdSpace.gutter,
                  OdSpace.x6,
                ),
                children: [
                  if (_problemText != null) ...[
                    Text(_problemText!, style: context.type.bodyLarge),
                    const SizedBox(height: OdSpace.x1),
                    OdButton(
                      label: 'Try again',
                      variant: OdButtonVariant.secondary,
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      },
                    ),
                  ] else ...[
                    if (mine == null) ..._starter(context) else ..._active(context, mine),
                    const SizedBox(height: OdSpace.x4),
                    Text('Up for something nearby', style: context.type.titleMedium),
                    const SizedBox(height: OdSpace.x1),
                    if (_people.isEmpty)
                      Text(
                        'Nobody nearby right now. Check back later.',
                        style: context.type.bodyMedium,
                      ),
                    for (final person in _people)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${person.firstName} · ${person.activity}'),
                        subtitle: Text(
                          [
                            person.distance,
                            if (person.timeLeft != null) person.timeLeft!,
                            if (person.why != null) person.why!,
                          ].join(' · '),
                        ),
                        trailing: person.youAsked
                            ? Text('Asked', style: context.type.labelMedium)
                            : TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _do(() async {
                                        final said = await _repo.join(person.id);
                                        await _load();
                                        if (mounted) _say(said);
                                      }),
                                child: const Text('I\'m in'),
                              ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _starter(BuildContext context) => [
    Text('What are you up for?', style: context.type.titleLarge),
    const SizedBox(height: OdSpace.x1),
    TextField(
      controller: _activity,
      maxLength: 30,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Badminton, chai, a walk…',
        counterText: '',
      ),
    ),
    const SizedBox(height: OdSpace.x1),
    Wrap(
      spacing: OdSpace.x1,
      children: [
        for (final minutes in _lengths)
          OdChip(
            label: minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h',
            selected: _minutes == minutes,
            onTap: () => setState(() => _minutes = minutes),
          ),
      ],
    ),
    const SizedBox(height: OdSpace.x1_5),
    OdButton(
      label: 'Start',
      expand: true,
      loading: _busy,
      onPressed: _start,
    ),
  ];

  List<Widget> _active(BuildContext context, MyRightNow mine) => [
    OdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You\'re up for ${mine.activity}', style: context.type.titleLarge),
          if (mine.timeLeft != null)
            Text(mine.timeLeft!, style: context.type.bodyMedium),
          if (mine.requests != null) ...[
            const SizedBox(height: OdSpace.x0_5),
            Text(mine.requests!, style: context.type.bodyMedium),
          ],
          const SizedBox(height: OdSpace.x1),
          OdButton(
            label: 'Stop',
            variant: OdButtonVariant.secondary,
            onPressed: _busy
                ? null
                : () => _do(() async {
                    await _repo.stop();
                    await _load();
                  }),
          ),
        ],
      ),
    ),
    if (_requests.isNotEmpty) ...[
      const SizedBox(height: OdSpace.x2),
      Text('They\'re in', style: context.type.titleMedium),
      for (final request in _requests)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(request.firstName),
          subtitle: request.sharedContext == null
              ? null
              : Text(request.sharedContext!),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _do(() async {
                        await _repo.decline(request.id);
                        await _load();
                      }),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _do(() async {
                        await _repo.accept(request.id);
                        ref.invalidate(conversationsProvider);
                        await _load();
                        if (mounted) {
                          _say('You\'re connected. Say hi in Chats.');
                        }
                      }),
                child: const Text('Say yes'),
              ),
            ],
          ),
        ),
    ],
  ];
}
