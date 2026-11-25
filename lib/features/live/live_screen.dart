import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/live.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../design_system/design_system.dart';

String _problem(Object e) => e is ApiError
    ? e.detail
    : 'Couldn\'t connect to the live video. Check your connection and try again.';

/// Circle Live: lives you may watch now, and going live yourself. Lives are announced on the socket only,
/// never by push.
class LivesScreen extends ConsumerStatefulWidget {
  const LivesScreen({super.key});

  @override
  ConsumerState<LivesScreen> createState() => _LivesScreenState();
}

class _LivesScreenState extends ConsumerState<LivesScreen> {
  List<LiveSession>? _lives;
  String? _loadError;
  final _title = TextEditingController();
  bool _busy = false;

  LiveRepository get _repo => ref.read(liveRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lives = await _repo.list();
      if (mounted) {
        setState(() {
          _lives = lives;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = _problem(e));
    }
  }

  Future<void> _goLive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final started = await _repo.start(title: _title.text);
      if (!mounted) return;
      _title.clear();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(initial: started, hosting: true)),
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_problem(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watch(LiveSession live) async {
    try {
      final joined = await _repo.join(live.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(initial: joined, hosting: false)),
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_problem(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      if (next.value?.type == 'live') _load();
    });
    final lives = _lives;
    return Scaffold(
      appBar: AppBar(title: const Text('Circle Live')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OdSpace.gutter, OdSpace.x1, OdSpace.gutter, OdSpace.x6),
        children: [
          Text(
            'Live video to your connections, up to an hour. It\'s never recorded, and only you see how many are watching.',
            style: context.type.bodyMedium,
          ),
          const SizedBox(height: OdSpace.x1_5),
          TextField(
            controller: _title,
            maxLength: ApiLive.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What\'s happening? (optional)', counterText: ''),
          ),
          const SizedBox(height: OdSpace.x1),
          OdButton(label: 'Go live', expand: true, loading: _busy, onPressed: _goLive),
          const SizedBox(height: OdSpace.x3),
          Text('Live now', style: context.type.titleMedium),
          if (_loadError != null)
            Text(_loadError!, style: context.type.bodyMedium)
          else if (lives == null)
            const Padding(
              padding: EdgeInsets.all(OdSpace.x2),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (lives.where((l) => l.live).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: OdSpace.x1),
              child: Text('No one you know is live right now.', style: context.type.bodyMedium),
            ),
          for (final live in lives ?? const <LiveSession>[])
            if (live.live)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: OdAvatar(name: live.hostFirstName, seed: live.id.hashCode, size: 44, ring: OdRing.live),
                title: Text(live.title ?? '${live.hostFirstName} is live'),
                subtitle: Text([live.hostFirstName, if (live.audience != null) live.audience!].join(' · ')),
                trailing: const OdLiveBadge(),
                onTap: () => _watch(live),
              ),
        ],
      ),
    );
  }
}

/// The live room: the host publishes camera and microphone; viewers only watch. Viewers renew their access
/// before it runs out (every 10 minutes), which is when the server re-checks blocks and audience.
class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key, required this.initial, required this.hosting});

  final LiveJoin initial;
  final bool hosting;

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  late LiveJoin _join = widget.initial;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  Timer? _renew;
  String? _problemText;
  bool _ended = false;

  LiveRepository get _repo => ref.read(liveRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    _renew?.cancel();
    unawaited(_disconnect());
    super.dispose();
  }

  Future<void> _connect() async {
    final access = _join.access;
    if (access.serverUrl.isEmpty || access.token.isEmpty) {
      setState(() => _problemText = 'Live video needs the video server (it doesn\'t run in demo mode).');
      return;
    }
    try {
      final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true));
      final events = room.createListener()
        ..on<lk.TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<lk.TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (mounted) setState(() => _ended = true);
        });
      _room = room;
      _events = events;
      await room.connect(access.serverUrl, access.token);
      if (widget.hosting) {
        await room.localParticipant?.setCameraEnabled(true);
        await room.localParticipant?.setMicrophoneEnabled(true);
      } else {
        _scheduleRenewal();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _problemText = _problem(e));
    }
  }

  /// A viewer's access lasts 10 minutes; renew a minute early. A refusal (blocked, ended) ends the watch.
  void _scheduleRenewal() {
    final expires = _join.access.expiresAt;
    final wait = expires == null
        ? const Duration(minutes: 9)
        : expires.difference(DateTime.now()) - const Duration(minutes: 1);
    _renew?.cancel();
    _renew = Timer(wait.isNegative ? Duration.zero : wait, () async {
      try {
        _join = await _repo.join(_join.session.id);
        _scheduleRenewal();
      } catch (_) {
        await _disconnect();
        if (mounted) setState(() => _ended = true);
      }
    });
  }

  Future<void> _disconnect() async {
    final room = _room;
    _room = null;
    await _events?.dispose();
    _events = null;
    try {
      await room?.disconnect();
      await room?.dispose();
    } catch (_) {
      // Already gone.
    }
  }

  Future<void> _leave() async {
    if (widget.hosting) {
      try {
        await _repo.end(_join.session.id);
      } catch (_) {
        // Ending is best-effort here; the server ends lives that run past the hour anyway.
      }
    }
    await _disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  lk.VideoTrack? get _videoTrack {
    final room = _room;
    if (room == null) return null;
    if (widget.hosting) {
      for (final pub in room.localParticipant?.videoTrackPublications ?? const <lk.LocalTrackPublication>[]) {
        final track = pub.track;
        if (track is lk.LocalVideoTrack) return track;
      }
      return null;
    }
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track is lk.VideoTrack) return track;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event?.type == 'live' && event!.data['id'] == _join.session.id && event.data['state'] == 'ENDED') {
        setState(() => _ended = true);
      }
    });
    final track = _videoTrack;
    final session = _join.session;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null && !_ended)
            lk.VideoTrackRenderer(
              track,
              mirrorMode: widget.hosting
                  ? lk.VideoViewMirrorMode.mirror
                  : lk.VideoViewMirrorMode.off,
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(OdSpace.x4),
                child: Text(
                  _ended
                      ? 'This live has ended.'
                      : (_problemText ?? (widget.hosting ? 'Starting your camera…' : 'Connecting…')),
                  textAlign: TextAlign.center,
                  style: context.type.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(OdSpace.gutter),
              child: Column(
                children: [
                  Row(
                    children: [
                      const OdLiveBadge(),
                      const SizedBox(width: OdSpace.x1),
                      Expanded(
                        child: Text(
                          session.title ?? (widget.hosting ? 'You\'re live' : '${session.hostFirstName} is live'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.titleMedium?.copyWith(color: Colors.white),
                        ),
                      ),
                      if (widget.hosting && _join.viewers != null)
                        Text('${_join.viewers} watching', style: context.type.labelMedium?.copyWith(color: Colors.white70)),
                    ],
                  ),
                  const Spacer(),
                  OdButton(
                    label: widget.hosting ? 'End live' : 'Leave',
                    variant: widget.hosting ? OdButtonVariant.danger : OdButtonVariant.secondary,
                    expand: true,
                    onPressed: _leave,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
