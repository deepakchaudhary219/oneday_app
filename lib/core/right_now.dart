import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// Someone nearby who is up for something right now: a first name, an activity and a distance band.
class RightNowPerson {
  const RightNowPerson({
    required this.id,
    required this.firstName,
    required this.activity,
    required this.distance,
    this.timeLeft,
    this.why,
    this.youAsked = false,
  });

  /// The session id (what "I'm in" answers).
  final String id;
  final String firstName;
  final String activity;
  final String distance;

  /// Coarse on purpose ("for about an hour"), never a countdown.
  final String? timeLeft;
  final String? why;
  final bool youAsked;

  /// From NearbyView.
  factory RightNowPerson.fromJson(Map<String, dynamic> j) => RightNowPerson(
    id: j['id'] as String,
    firstName: j['firstName'] as String? ?? '',
    activity: j['activity'] as String? ?? '',
    distance: j['distance'] as String? ?? '',
    timeLeft: j['timeLeft'] as String?,
    why: j['whyYouSeeThis'] as String?,
    youAsked: j['youAsked'] as bool? ?? false,
  );
}

/// Your own Right Now, while it lasts.
class MyRightNow {
  const MyRightNow({required this.activity, this.timeLeft, this.requests});

  final String activity;
  final String? timeLeft;

  /// The server's line about who asked ("2 people are in"), never a list of faces until you look.
  final String? requests;

  /// From MySessionView.
  factory MyRightNow.fromJson(Map<String, dynamic> j) => MyRightNow(
    activity: j['activity'] as String? ?? '',
    timeLeft: j['timeLeft'] as String?,
    requests: j['requests'] as String?,
  );
}

/// Someone who said "I'm in" to your Right Now.
class RightNowRequest {
  const RightNowRequest({
    required this.id,
    required this.firstName,
    this.sharedContext,
  });

  final String id;
  final String firstName;
  final String? sharedContext;

  factory RightNowRequest.fromJson(Map<String, dynamic> j) => RightNowRequest(
    id: j['requestId'] as String,
    firstName: j['firstName'] as String? ?? '',
    sharedContext: j['sharedContext'] as String?,
  );
}

/// Right Now isn't open in this city yet (it opens per city once enough people use OneDay there).
class RightNowUnavailable implements Exception {
  const RightNowUnavailable();
}

abstract interface class RightNowRepository {
  /// Null when you haven't started one (or it ended).
  Future<MyRightNow?> mine();

  /// 30 to 120 minutes. Throws [LocationRequired] or [RightNowUnavailable].
  Future<MyRightNow> start(String activity, {int minutes = 60});

  Future<void> stop();

  /// Throws [LocationRequired] or [RightNowUnavailable].
  Future<List<RightNowPerson>> nearby();

  /// Returns the server's line ("Asked. If they say yes, a chat opens.").
  Future<String> join(String sessionId);

  Future<List<RightNowRequest>> requests();

  /// Opens a chat with them: returns the new connection's conversation id.
  Future<String?> accept(String requestId);

  /// Silent for them.
  Future<void> decline(String requestId);
}

class ApiRightNow implements RightNowRepository {
  ApiRightNow(this.api);

  final ApiClient api;

  static const minMinutes = 30;
  static const maxMinutes = 120;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      // Off in this city: the server answers as if Right Now didn't exist.
      if (e.status == 404) throw const RightNowUnavailable();
      rethrow;
    }
  }

  @override
  Future<MyRightNow?> mine() => _guard(() async {
    final json = await api.get('/right-now/mine'); // 204 when none
    return json is Map ? MyRightNow.fromJson(json.cast<String, dynamic>()) : null;
  });

  @override
  Future<MyRightNow> start(String activity, {int minutes = 60}) =>
      _guard(() async {
        final json = await api.post(
          '/right-now',
          body: {'activity': activity.trim(), 'minutes': minutes},
        );
        return MyRightNow.fromJson(json as Map<String, dynamic>);
      });

  @override
  Future<void> stop() => _guard(() => api.delete('/right-now'));

  @override
  Future<List<RightNowPerson>> nearby() => _guard(
    () async => [
      for (final p
          in (await api.get('/right-now') as List).cast<Map<String, dynamic>>())
        RightNowPerson.fromJson(p),
    ],
  );

  @override
  Future<String> join(String sessionId) => _guard(() async {
    final json = await api.post('/right-now/$sessionId/join');
    return (json is Map ? json['message'] as String? : null) ??
        'Asked. If they say yes, a chat opens.';
  });

  @override
  Future<List<RightNowRequest>> requests() => _guard(
    () async => [
      for (final r
          in (await api.get('/right-now/requests') as List)
              .cast<Map<String, dynamic>>())
        RightNowRequest.fromJson(r),
    ],
  );

  @override
  Future<String?> accept(String requestId) => _guard(() async {
    final json = await api.post('/right-now/requests/$requestId/accept');
    return json is Map ? json['conversationId'] as String? : null;
  });

  @override
  Future<void> decline(String requestId) =>
      _guard(() => api.post('/right-now/requests/$requestId/decline'));
}

class FakeRightNow implements RightNowRepository {
  MyRightNow? _mine;
  final asked = <String>{};
  final _requests = <RightNowRequest>[
    const RightNowRequest(
      id: 'rq1',
      firstName: 'Kabir',
      sharedContext: 'You both play badminton',
    ),
  ];

  @override
  Future<MyRightNow?> mine() async => _mine;

  @override
  Future<MyRightNow> start(String activity, {int minutes = 60}) async =>
      _mine = MyRightNow(
        activity: activity.trim(),
        timeLeft: minutes >= 75 ? 'for a while yet' : 'for about an hour',
        requests: _requests.isEmpty ? null : 'Someone is in',
      );

  @override
  Future<void> stop() async => _mine = null;

  @override
  Future<List<RightNowPerson>> nearby() async => [
    RightNowPerson(
      id: 'rn1',
      firstName: 'Meera',
      activity: 'badminton',
      distance: 'Under 1 km',
      timeLeft: 'for about an hour',
      why: 'You both play badminton',
      youAsked: asked.contains('rn1'),
    ),
    RightNowPerson(
      id: 'rn2',
      firstName: 'Zoya',
      activity: 'chai and a walk',
      distance: '1 to 5 km',
      timeLeft: 'for a little longer',
      youAsked: asked.contains('rn2'),
    ),
  ];

  @override
  Future<String> join(String sessionId) async {
    asked.add(sessionId);
    return 'Asked. If they say yes, a chat opens.';
  }

  @override
  Future<List<RightNowRequest>> requests() async =>
      _mine == null ? const [] : List.of(_requests);

  @override
  Future<String?> accept(String requestId) async {
    _requests.removeWhere((r) => r.id == requestId);
    return 'conv-$requestId';
  }

  @override
  Future<void> decline(String requestId) async =>
      _requests.removeWhere((r) => r.id == requestId);
}
