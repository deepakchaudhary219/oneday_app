import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/calls.dart';
import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/realtime.dart';
import '../../design_system/design_system.dart';

final callsApiProvider = Provider<CallsApi?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? null : CallsApi(api);
});

/// Starts a call from a chat. Calls open once both people have written; the server says so otherwise.
Future<void> startCall(BuildContext context, WidgetRef ref, Conversation conversation) async {
  final calls = ref.read(callsApiProvider);
  if (calls == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calls need the OneDay server (they don\'t run in demo mode).')),
    );
    return;
  }
  try {
    final call = await calls.start(conversation.id);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CallScreen(initial: call)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e is ApiError ? e.detail : 'Couldn\'t start the call.')),
    );
  }
}

/// Opens the incoming-call screen for a pushed `call` event, unless that call is already on screen.
void showIncomingCall(BuildContext context, RealtimeEvent event) {
  final call = CallState.fromJson(event.data);
  if (!call.incoming || !call.ringing || CallScreen.onScreen == call.id) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CallScreen(initial: call)),
  );
}

/// A Layered Video call: voice first; blurred, then clear video only as far as both people choose; either can
/// step down instantly. Media goes peer to peer (never recorded); the server relays only signalling.
///
/// Blurred video is made blurry before it leaves the phone: the camera track is sent at 1/16 of its
/// resolution, and the receiving side also blurs what it shows.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.initial});

  final CallState initial;

  /// The call currently shown, so a repeated `call` event doesn't open it twice.
  static String? onScreen;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late CallState _call = widget.initial;
  RTCPeerConnection? _pc;
  RTCRtpTransceiver? _video;
  MediaStream? _mic;
  MediaStream? _camera;
  final _remote = RTCVideoRenderer();
  final _local = RTCVideoRenderer();
  final _pendingIce = <RTCIceCandidate>[];

  /// Signals that arrive before the connection is set up (the offer can beat the callee's setup).
  final _early = <(String, String)>[];
  bool _remoteSet = false;
  bool _muted = false;
  bool _connecting = false;
  bool _offered = false;

  /// The connection has its tracks and can take signals.
  bool _ready = false;
  String? _problem;

  CallsApi get _api => ref.read(callsApiProvider)!;

  @override
  void initState() {
    super.initState();
    CallScreen.onScreen = _call.id;
    unawaited(_remote.initialize());
    unawaited(_local.initialize());
    // An outgoing call can already be active by the time this opens; an incoming one waits for Accept.
    if (_call.active) unawaited(_connect());
  }

  @override
  void dispose() {
    if (CallScreen.onScreen == _call.id) CallScreen.onScreen = null;
    unawaited(_teardown());
    _remote.dispose();
    _local.dispose();
    super.dispose();
  }

  Future<void> _teardown() async {
    for (final stream in [_mic, _camera]) {
      for (final track in stream?.getTracks() ?? const <MediaStreamTrack>[]) {
        await track.stop();
      }
      await stream?.dispose();
    }
    _mic = null;
    _camera = null;
    await _pc?.close();
    _pc = null;
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() => _problem = e is ApiError ? e.detail : 'The call ran into a problem.');
  }

  /// Sets up the peer connection with the microphone and an empty video slot that layers fill later, so moving
  /// between layers never needs a new negotiation.
  Future<void> _connect() async {
    if (_pc != null || _connecting) return;
    _connecting = true;
    try {
      final pc = await createPeerConnection({
        ...await _api.iceServers(),
        'sdpSemantics': 'unified-plan',
      });
      _pc = pc;
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        unawaited(
          _api.signal(
            _call.id,
            CallSignal(
              'ICE',
              jsonEncode({
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              }),
            ),
          ).catchError((Object _) {}),
        );
      };
      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          setState(() => _remote.srcObject = event.streams.first);
        }
      };
      final mic = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      _mic = mic;
      for (final track in mic.getAudioTracks()) {
        await pc.addTrack(track, mic);
      }
      _video = await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      _ready = true;
      // The caller makes the offer once the call is active.
      if (!_call.incoming) await _offer();
      final early = List.of(_early);
      _early.clear();
      for (final (kind, payload) in early) {
        await _onSignal(kind, payload);
      }
      await _applyLayer();
    } catch (e) {
      _fail(e);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _offer() async {
    final pc = _pc;
    if (pc == null || _offered) return;
    _offered = true;
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    await _api.signal(_call.id, CallSignal('OFFER', jsonEncode({'sdp': offer.sdp, 'type': offer.type})));
  }

  Future<void> _onSignal(String kind, String payload) async {
    final pc = _pc;
    if (pc == null || !_ready) {
      _early.add((kind, payload));
      return;
    }
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      switch (kind) {
        case 'OFFER':
          await pc.setRemoteDescription(RTCSessionDescription(json['sdp'] as String?, json['type'] as String?));
          await _flushIce();
          final answer = await pc.createAnswer({});
          await pc.setLocalDescription(answer);
          await _api.signal(_call.id, CallSignal('ANSWER', jsonEncode({'sdp': answer.sdp, 'type': answer.type})));
        case 'ANSWER':
          await pc.setRemoteDescription(RTCSessionDescription(json['sdp'] as String?, json['type'] as String?));
          await _flushIce();
        case 'ICE':
          final candidate = RTCIceCandidate(
            json['candidate'] as String?,
            json['sdpMid'] as String?,
            (json['sdpMLineIndex'] as num?)?.toInt(),
          );
          if (_remoteSet) {
            await pc.addCandidate(candidate);
          } else {
            _pendingIce.add(candidate);
          }
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _flushIce() async {
    _remoteSet = true;
    for (final c in _pendingIce) {
      await _pc?.addCandidate(c);
    }
    _pendingIce.clear();
  }

  /// Sends exactly what the current layer allows: no video at Voice, 1/16-resolution video at Blurred, full
  /// video at Clear.
  Future<void> _applyLayer() async {
    final sender = _video?.sender;
    if (sender == null) return;
    try {
      if (_call.layer == CallLayer.voice) {
        await sender.replaceTrack(null);
        for (final t in _camera?.getTracks() ?? const <MediaStreamTrack>[]) {
          await t.stop();
        }
        await _camera?.dispose();
        _camera = null;
        if (mounted) setState(() => _local.srcObject = null);
        return;
      }
      final camera = _camera ??= await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': 'user'},
      });
      final track = camera.getVideoTracks().first;
      final parameters = sender.parameters;
      for (final encoding in parameters.encodings ?? const <RTCRtpEncoding>[]) {
        encoding.scaleResolutionDownBy = _call.layer == CallLayer.blurred ? 16 : 1;
      }
      await sender.setParameters(parameters);
      await sender.replaceTrack(track);
      if (mounted) setState(() => _local.srcObject = camera);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _updated(CallState next) async {
    final wasActive = _call.active;
    final layerChanged = next.layer != _call.layer;
    setState(() => _call = next);
    if (next.ended) {
      await _teardown();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (next.active && !wasActive) await _connect();
    if (layerChanged) await _applyLayer();
  }

  Future<void> _act(Future<CallState> Function() action) async {
    try {
      await _updated(await action());
    } catch (e) {
      _fail(e);
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.od;
    ref.listen(realtimeEventsProvider, (_, next) {
      final event = next.value;
      if (event == null) return;
      if (event.type == 'call' && event.data['id'] == _call.id) {
        unawaited(_updated(CallState.fromJson(event.data)));
      } else if (event.type == 'call-signal' && event.data['callId'] == _call.id) {
        unawaited(_onSignal(event.data['kind'] as String? ?? '', event.data['payload'] as String? ?? '{}'));
      }
    });
    final video = _call.layer != CallLayer.voice && _remote.srcObject != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (video)
            ImageFiltered(
              enabled: _call.layer == CallLayer.blurred,
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: RTCVideoView(_remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            )
          else
            Center(child: OdAvatar(name: _call.firstName, seed: _call.connectionId.hashCode, size: 120)),
          if (_local.srcObject != null)
            Positioned(
              right: OdSpace.gutter,
              top: MediaQuery.paddingOf(context).top + OdSpace.x2,
              width: 96,
              height: 128,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(OdRadius.md),
                child: ImageFiltered(
                  enabled: _call.layer == CallLayer.blurred,
                  imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(OdSpace.gutter),
              child: Column(
                children: [
                  Text(_call.firstName, style: context.type.headlineSmall?.copyWith(color: Colors.white)),
                  Text(
                    _call.ringing
                        ? (_call.incoming ? 'Calling you · voice first' : 'Ringing…')
                        : _call.layer.label,
                    style: context.type.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  if (_call.active && _call.theyAreReadyForMore)
                    Text(
                      '${_call.firstName} is open to more video when you are.',
                      style: context.type.labelMedium?.copyWith(color: Colors.white70),
                    ),
                  if (_problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: OdSpace.x1),
                      child: Text(_problem!, style: context.type.bodyMedium?.copyWith(color: c.danger)),
                    ),
                  const Spacer(),
                  if (_call.active)
                    Wrap(
                      spacing: OdSpace.x1,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final layer in CallLayer.values)
                          OdChip(
                            label: layer.label,
                            selected: _call.youWant == layer,
                            onTap: () => _act(() => _api.want(_call.id, layer)),
                          ),
                      ],
                    ),
                  const SizedBox(height: OdSpace.x3),
                  if (_call.ringing && _call.incoming)
                    Row(
                      children: [
                        Expanded(
                          child: OdButton(
                            label: 'Decline',
                            variant: OdButtonVariant.danger,
                            onPressed: () => _act(() => _api.decline(_call.id)),
                          ),
                        ),
                        const SizedBox(width: OdSpace.x2),
                        Expanded(
                          child: OdButton(
                            label: 'Accept',
                            onPressed: () => _act(() => _api.accept(_call.id)),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OdIconButton(
                          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          semanticLabel: _muted ? 'Unmute' : 'Mute',
                          background: Colors.white24,
                          foreground: Colors.white,
                          onPressed: _call.active ? _toggleMute : null,
                        ),
                        const SizedBox(width: OdSpace.x4),
                        OdIconButton(
                          icon: Icons.call_end_rounded,
                          semanticLabel: 'End call',
                          background: c.danger,
                          foreground: Colors.white,
                          onPressed: () => _act(() => _api.end(_call.id)),
                        ),
                      ],
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
