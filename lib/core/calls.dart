import 'network/api_client.dart';

/// How much of each other people see on a call. Every call starts as voice and moves up only as far as both
/// people choose; either can step down at once.
enum CallLayer {
  voice('VOICE', 'Voice'),
  blurred('BLURRED', 'Blurred video'),
  clear('CLEAR', 'Video');

  const CallLayer(this.api, this.label);

  final String api;
  final String label;

  static CallLayer fromApi(Object? value) => values.firstWhere(
    (l) => l.api == value,
    orElse: () => CallLayer.voice,
  );
}

class CallState {
  const CallState({
    required this.id,
    required this.connectionId,
    required this.firstName,
    required this.incoming,
    required this.status,
    required this.layer,
    required this.youWant,
    this.theyAreReadyForMore = false,
    this.endReason,
  });

  final String id;
  final String connectionId;
  final String firstName;
  final bool incoming;

  /// `RINGING`, `ACTIVE` or `ENDED`.
  final String status;

  /// What the call runs at: the lower of the two choices.
  final CallLayer layer;
  final CallLayer youWant;

  /// The other person would go further than the current layer (shown as a gentle hint, never a push).
  final bool theyAreReadyForMore;
  final String? endReason;

  bool get ringing => status == 'RINGING';

  bool get active => status == 'ACTIVE';

  bool get ended => status == 'ENDED';

  /// From CallView.
  factory CallState.fromJson(Map<String, dynamic> j) => CallState(
    id: j['id'] as String,
    connectionId: j['connectionId'] as String? ?? '',
    firstName: j['firstName'] as String? ?? '',
    incoming: j['direction'] == 'INCOMING',
    status: j['status'] as String? ?? 'RINGING',
    layer: CallLayer.fromApi(j['layer']),
    youWant: CallLayer.fromApi(j['youWant']),
    theyAreReadyForMore: j['theyAreReadyForMore'] as bool? ?? false,
    endReason: j['endReason'] as String?,
  );
}

/// One WebRTC signalling message relayed by the server.
class CallSignal {
  const CallSignal(this.kind, this.payload);

  /// `OFFER`, `ANSWER` or `ICE`.
  final String kind;

  /// JSON: a session description (`{sdp, type}`) or an ICE candidate (`{candidate, sdpMid, sdpMLineIndex}`).
  final String payload;
}

class CallsApi {
  CallsApi(this.api);

  final ApiClient api;

  CallState _call(dynamic json) => CallState.fromJson(json as Map<String, dynamic>);

  /// Opens once both people have written in the chat (`CHAT_FIRST` otherwise).
  Future<CallState> start(String connectionId) async =>
      _call(await api.post('/connections/$connectionId/calls'));

  Future<CallState> get(String callId) async => _call(await api.get('/calls/$callId'));

  Future<CallState> accept(String callId) async => _call(await api.post('/calls/$callId/accept'));

  Future<CallState> decline(String callId) async => _call(await api.post('/calls/$callId/decline'));

  Future<CallState> end(String callId) async => _call(await api.post('/calls/$callId/end'));

  Future<CallState> want(String callId, CallLayer layer) async =>
      _call(await api.put('/calls/$callId/layer', body: {'wants': layer.api}));

  Future<void> signal(String callId, CallSignal signal) => api.post(
    '/calls/$callId/signal',
    body: {'kind': signal.kind, 'payload': signal.payload},
  );

  /// STUN and short-lived TURN credentials, in the shape WebRTC takes (`{iceServers: [...]}`).
  Future<Map<String, dynamic>> iceServers() async {
    final json = await api.get('/calls/ice-servers') as Map<String, dynamic>;
    return {
      'iceServers': [
        for (final s in (json['iceServers'] as List? ?? const []).cast<Map<String, dynamic>>())
          {
            'urls': s['urls'],
            if (s['username'] != null) 'username': s['username'],
            if (s['credential'] != null) 'credential': s['credential'],
          },
      ],
    };
  }
}
