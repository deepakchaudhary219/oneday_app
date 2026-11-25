import 'network/api_client.dart';

/// A Circle Live: video to your Connections or to one Collaborative Thread, up to 60 minutes, never recorded.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.hostFirstName,
    required this.live,
    this.title,
    this.audience,
    this.threadId,
    this.endsBy,
  });

  final String id;
  final String hostFirstName;
  final bool live;
  final String? title;

  /// Who can watch, in the server's words ("Your connections", a thread's title).
  final String? audience;
  final String? threadId;
  final DateTime? endsBy;

  /// From LiveView.
  factory LiveSession.fromJson(Map<String, dynamic> j) => LiveSession(
    id: j['id'] as String,
    hostFirstName: j['hostFirstName'] as String? ?? '',
    live: j['state'] == 'LIVE',
    title: j['title'] as String?,
    audience: j['audience'] as String?,
    threadId: j['threadId'] as String?,
    endsBy: j['endsBy'] == null ? null : DateTime.parse(j['endsBy'] as String).toLocal(),
  );
}

/// Where and how to connect to the video server (a LiveKit-compatible SFU). Hosts may publish; viewers may only
/// subscribe, for 10 minutes at a time.
class LiveAccess {
  const LiveAccess({required this.serverUrl, required this.token, this.expiresAt});

  final String serverUrl;
  final String token;
  final DateTime? expiresAt;

  factory LiveAccess.fromJson(Map<String, dynamic> j) => LiveAccess(
    serverUrl: j['serverUrl'] as String,
    token: j['token'] as String,
    expiresAt: j['expiresAt'] == null ? null : DateTime.parse(j['expiresAt'] as String).toLocal(),
  );
}

class LiveJoin {
  const LiveJoin(this.session, this.access, {this.viewers});

  final LiveSession session;
  final LiveAccess access;

  /// The host's own count; viewers never see it.
  final int? viewers;

  factory LiveJoin.fromJson(Map<String, dynamic> j) => LiveJoin(
    LiveSession.fromJson((j['live'] as Map).cast<String, dynamic>()),
    LiveAccess.fromJson((j['access'] as Map).cast<String, dynamic>()),
    viewers: (j['viewers'] as num?)?.toInt(),
  );
}

abstract interface class LiveRepository {
  /// Lives you may watch right now.
  Future<List<LiveSession>> list();

  /// Goes live to your Connections, or to one thread with [threadId].
  Future<LiveJoin> start({String? title, String? threadId});

  /// The host's own view (and a fresh token).
  Future<LiveJoin> host(String liveId);

  /// Call again before [LiveAccess.expiresAt] to keep watching.
  Future<LiveJoin> join(String liveId);

  Future<void> end(String liveId);
}

class ApiLive implements LiveRepository {
  ApiLive(this.api);

  final ApiClient api;

  static const maxTitle = 80;

  @override
  Future<List<LiveSession>> list() async => [
    for (final l in (await api.get('/live') as List).cast<Map<String, dynamic>>())
      LiveSession.fromJson(l),
  ];

  @override
  Future<LiveJoin> start({String? title, String? threadId}) async {
    final name = title?.trim() ?? '';
    return LiveJoin.fromJson(
      await api.post(
            '/live',
            body: {
              if (name.isNotEmpty) 'title': name,
              'threadId': ?threadId,
            },
          )
          as Map<String, dynamic>,
    );
  }

  @override
  Future<LiveJoin> host(String liveId) async =>
      LiveJoin.fromJson(await api.get('/live/$liveId/host') as Map<String, dynamic>);

  @override
  Future<LiveJoin> join(String liveId) async =>
      LiveJoin.fromJson(await api.post('/live/$liveId/join') as Map<String, dynamic>);

  @override
  Future<void> end(String liveId) => api.post('/live/$liveId/end');
}

/// Demo mode: one friend live, no video server.
class FakeLive implements LiveRepository {
  @override
  Future<List<LiveSession>> list() async => const [
    LiveSession(
      id: 'l1',
      hostFirstName: 'Zoya',
      live: true,
      title: 'Soundcheck at the gig',
      audience: 'Her connections',
    ),
  ];

  @override
  Future<LiveJoin> start({String? title, String? threadId}) async => LiveJoin(
    LiveSession(id: 'mine', hostFirstName: 'You', live: true, title: title),
    const LiveAccess(serverUrl: '', token: ''),
    viewers: 0,
  );

  @override
  Future<LiveJoin> host(String liveId) => start();

  @override
  Future<LiveJoin> join(String liveId) async => LiveJoin(
    (await list()).first,
    const LiveAccess(serverUrl: '', token: ''),
  );

  @override
  Future<void> end(String liveId) async {}
}
