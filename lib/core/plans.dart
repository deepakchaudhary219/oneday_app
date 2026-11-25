import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

DateTime _time(Object? value) => DateTime.parse(value! as String).toLocal();

/// "Today 7:30 pm", "Tomorrow 10:00 am", "Sat 14 Nov, 6:00 pm": when something happens, in local time.
String whenLabel(DateTime at, DateTime now) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final time =
      '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'am' : 'pm'}';
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'Today $time';
  if (days == 1) return 'Tomorrow $time';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[local.weekday - 1]} ${local.day} ${months[local.month - 1]}, $time';
}

/// A small meet-up nearby (3 to 12 people, always at a Safety-Verified Meeting Point), as the list shows it.
class PlanCard {
  const PlanCard({
    required this.id,
    required this.title,
    required this.activity,
    required this.host,
    required this.place,
    required this.startsAt,
    required this.spotsLeft,
    this.why,
    this.you,
  });

  final String id;
  final String title;
  final String activity;
  final String host;
  final String place;
  final DateTime startsAt;
  final int spotsLeft;
  final String? why;

  /// Null, `ASKED` or `IN`. A decline reads as `ASKED` forever: declines are silent.
  final String? you;

  factory PlanCard.fromJson(Map<String, dynamic> j) => PlanCard(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? (j['activity'] as String? ?? 'Plan'),
    activity: j['activity'] as String? ?? '',
    host: j['hostFirstName'] as String? ?? '',
    place: j['place'] as String? ?? '',
    startsAt: _time(j['startsAt']),
    spotsLeft: (j['spotsLeft'] as num?)?.toInt() ?? 0,
    why: j['whyYouSeeThis'] as String?,
    you: j['you'] as String?,
  );
}

/// The full plan. [going] is filled only for members.
class PlanDetail {
  const PlanDetail({
    required this.id,
    required this.title,
    required this.activity,
    required this.host,
    required this.place,
    required this.startsAt,
    required this.endsAt,
    required this.spotsLeft,
    this.address,
    this.status = 'OPEN',
    this.yourStatus,
    this.going = const [],
  });

  final String id;
  final String title;
  final String activity;
  final String host;
  final String place;
  final String? address;
  final DateTime startsAt;
  final DateTime endsAt;
  final int spotsLeft;

  /// `OPEN`, `CANCELLED` or `ENDED`.
  final String status;

  /// Null, `HOST`, `REQUESTED`, `APPROVED` or `LEFT`.
  final String? yourStatus;
  final List<String> going;

  bool get hosting => yourStatus == 'HOST';

  /// In the Room: the host and approved members.
  bool get member => yourStatus == 'HOST' || yourStatus == 'APPROVED';

  bool get asked => yourStatus == 'REQUESTED';

  factory PlanDetail.fromJson(Map<String, dynamic> j) => PlanDetail(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? (j['activity'] as String? ?? 'Plan'),
    activity: j['activity'] as String? ?? '',
    host: j['hostFirstName'] as String? ?? '',
    place: j['place'] as String? ?? '',
    address: j['address'] as String?,
    startsAt: _time(j['startsAt']),
    endsAt: _time(j['endsAt']),
    spotsLeft: (j['spotsLeft'] as num?)?.toInt() ?? 0,
    status: j['status'] as String? ?? 'OPEN',
    yourStatus: j['yourStatus'] as String?,
    going: (j['going'] as List? ?? const []).cast<String>(),
  );
}

/// Someone asking to join, as the host sees them: a first name and what you share, under a per-plan handle.
class JoinRequest {
  const JoinRequest({
    required this.handle,
    required this.firstName,
    this.sharedContext,
  });

  final String handle;
  final String firstName;
  final String? sharedContext;

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
    handle: j['handle'] as String,
    firstName: j['firstName'] as String? ?? '',
    sharedContext: j['sharedContext'] as String?,
  );
}

class RoomMessage {
  const RoomMessage({
    required this.id,
    required this.firstName,
    required this.body,
    required this.mine,
    required this.sentAt,
  });

  final String id;
  final String firstName;
  final String body;
  final bool mine;
  final DateTime sentAt;

  factory RoomMessage.fromJson(Map<String, dynamic> j) => RoomMessage(
    id: j['id'] as String,
    firstName: j['firstName'] as String? ?? '',
    body: j['body'] as String? ?? '',
    mine: j['mine'] as bool? ?? false,
    sentAt: _time(j['sentAt']),
  );
}

/// A staff-curated public place where plans and dates can happen.
class MeetingPoint {
  const MeetingPoint({
    required this.id,
    required this.name,
    this.address,
    this.distanceKm,
  });

  final String id;
  final String name;
  final String? address;
  final double? distanceKm;

  factory MeetingPoint.fromJson(Map<String, dynamic> j) => MeetingPoint(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    address: j['address'] as String?,
    distanceKm: (j['distanceKm'] as num?)?.toDouble(),
  );
}

abstract interface class PlansRepository {
  /// Throws [LocationRequired] until the area is shared.
  Future<List<PlanCard>> nearby();

  Future<List<PlanDetail>> mine();

  Future<PlanDetail> plan(String planId);

  /// Asks the host; they approve or (silently) don't.
  Future<PlanDetail> join(String planId);

  Future<void> leave(String planId);

  Future<List<JoinRequest>> requests(String planId);

  Future<void> decide(String planId, String handle, {required bool approve});

  /// Oldest first.
  Future<List<RoomMessage>> room(String planId);

  /// Throws [EmpathyCheck] when the Empathy Mirror asks for a second look.
  Future<RoomMessage> say(String planId, String body, {bool sendAnyway = false});

  Future<List<MeetingPoint>> meetingPoints();

  Future<PlanDetail> host({
    required String meetingPointId,
    required String activity,
    required DateTime startsAt,
    required DateTime endsAt,
    String? title,
    int capacity = 6,
  });
}

class ApiPlans implements PlansRepository {
  ApiPlans(this.api);

  final ApiClient api;

  static const minCapacity = 3;
  static const maxCapacity = 12;

  Future<T> _located<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      rethrow;
    }
  }

  List<Map<String, dynamic>> _list(dynamic json) =>
      (json as List).cast<Map<String, dynamic>>();

  @override
  Future<List<PlanCard>> nearby() => _located(
    () async => [
      for (final p in _list(await api.get('/plans'))) PlanCard.fromJson(p),
    ],
  );

  @override
  Future<List<PlanDetail>> mine() async => [
    for (final p in _list(await api.get('/plans/mine'))) PlanDetail.fromJson(p),
  ];

  @override
  Future<PlanDetail> plan(String planId) async => PlanDetail.fromJson(
    await api.get('/plans/$planId') as Map<String, dynamic>,
  );

  @override
  Future<PlanDetail> join(String planId) async => PlanDetail.fromJson(
    await api.post('/plans/$planId/join') as Map<String, dynamic>,
  );

  @override
  Future<void> leave(String planId) => api.post('/plans/$planId/leave');

  @override
  Future<List<JoinRequest>> requests(String planId) async => [
    for (final r in _list(await api.get('/plans/$planId/requests')))
      JoinRequest.fromJson(r),
  ];

  @override
  Future<void> decide(String planId, String handle, {required bool approve}) =>
      api.post(
        '/plans/$planId/requests/$handle/${approve ? 'approve' : 'decline'}',
      );

  @override
  Future<List<RoomMessage>> room(String planId) async {
    final list = _list(
      await api.get('/plans/$planId/room', query: {'limit': 50}),
    );
    // The server pages newest first; the Room reads oldest first.
    return [for (final m in list.reversed) RoomMessage.fromJson(m)];
  }

  @override
  Future<RoomMessage> say(
    String planId,
    String body, {
    bool sendAnyway = false,
  }) async {
    try {
      final json = await api.post(
        '/plans/$planId/room',
        body: {'body': body, 'sendAnyway': sendAnyway},
      );
      return RoomMessage.fromJson(json as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.code == 'EMPATHY_CHECK') throw EmpathyCheck(e.detail);
      rethrow;
    }
  }

  @override
  Future<List<MeetingPoint>> meetingPoints() => _located(
    () async => [
      for (final p in _list(await api.get('/meeting-points')))
        MeetingPoint.fromJson(p),
    ],
  );

  @override
  Future<PlanDetail> host({
    required String meetingPointId,
    required String activity,
    required DateTime startsAt,
    required DateTime endsAt,
    String? title,
    int capacity = 6,
  }) => _located(() async {
    final name = title?.trim() ?? '';
    final json = await api.post(
      '/plans',
      body: {
        'meetingPointId': meetingPointId,
        'activity': activity.trim(),
        if (name.isNotEmpty) 'title': name,
        'capacity': capacity,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
      },
    );
    return PlanDetail.fromJson(json as Map<String, dynamic>);
  });
}

/// Demo mode: two plans nearby, and whatever is hosted or joined in this session.
class FakePlans implements PlansRepository {
  FakePlans({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _status = <String, String>{};
  final _rooms = <String, List<RoomMessage>>{};
  final _hosted = <PlanDetail>[];
  final pendingRequests = <String, List<JoinRequest>>{};

  static const _points = [
    MeetingPoint(
      id: 'mp1',
      name: 'Third Wave Coffee, Koramangala',
      address: '5th Block, Koramangala',
      distanceKm: 0.8,
    ),
    MeetingPoint(
      id: 'mp2',
      name: 'Cubbon Park, Bandstand',
      address: 'Kasturba Road',
      distanceKm: 3.4,
    ),
  ];

  List<PlanDetail> get _seed {
    final now = _clock();
    return [
      PlanDetail(
        id: 'pl1',
        title: 'Sunday badminton doubles',
        activity: 'badminton',
        host: 'Kabir',
        place: 'Cubbon Park, Bandstand',
        address: 'Kasturba Road',
        startsAt: now.add(const Duration(hours: 20)),
        endsAt: now.add(const Duration(hours: 22)),
        spotsLeft: 3,
        yourStatus: _status['pl1'],
        going: _status['pl1'] == 'APPROVED' ? const ['Kabir', 'Meera'] : const [],
      ),
      PlanDetail(
        id: 'pl2',
        title: 'Filter coffee and board games',
        activity: 'board games',
        host: 'Ananya',
        place: 'Third Wave Coffee, Koramangala',
        address: '5th Block, Koramangala',
        startsAt: now.add(const Duration(hours: 4)),
        endsAt: now.add(const Duration(hours: 6)),
        spotsLeft: 2,
        yourStatus: _status['pl2'],
      ),
    ];
  }

  List<PlanDetail> get _all => [..._hosted, ..._seed];

  @override
  Future<List<PlanCard>> nearby() async => [
    for (final p in _seed)
      PlanCard(
        id: p.id,
        title: p.title,
        activity: p.activity,
        host: p.host,
        place: p.place,
        startsAt: p.startsAt,
        spotsLeft: p.spotsLeft,
        why: 'You both play ${p.activity}',
        you: switch (p.yourStatus) {
          'APPROVED' => 'IN',
          'REQUESTED' => 'ASKED',
          _ => null,
        },
      ),
  ];

  @override
  Future<List<PlanDetail>> mine() async => [
    for (final p in _all)
      if (p.yourStatus != null && p.yourStatus != 'LEFT') p,
  ];

  @override
  Future<PlanDetail> plan(String planId) async =>
      _all.firstWhere((p) => p.id == planId);

  @override
  Future<PlanDetail> join(String planId) async {
    // The demo host of the first plan says yes at once, so the Room can be seen.
    _status[planId] = planId == 'pl1' ? 'APPROVED' : 'REQUESTED';
    return plan(planId);
  }

  @override
  Future<void> leave(String planId) async => _status[planId] = 'LEFT';

  @override
  Future<List<JoinRequest>> requests(String planId) async =>
      List.of(pendingRequests[planId] ?? const []);

  @override
  Future<void> decide(
    String planId,
    String handle, {
    required bool approve,
  }) async => pendingRequests[planId]?.removeWhere((r) => r.handle == handle);

  @override
  Future<List<RoomMessage>> room(String planId) async =>
      List.of(_rooms[planId] ?? const []);

  @override
  Future<RoomMessage> say(
    String planId,
    String body, {
    bool sendAnyway = false,
  }) async {
    final list = _rooms.putIfAbsent(planId, () => []);
    final message = RoomMessage(
      id: 'rm${list.length}',
      firstName: 'You',
      body: body,
      mine: true,
      sentAt: _clock(),
    );
    list.add(message);
    return message;
  }

  @override
  Future<List<MeetingPoint>> meetingPoints() async => _points;

  @override
  Future<PlanDetail> host({
    required String meetingPointId,
    required String activity,
    required DateTime startsAt,
    required DateTime endsAt,
    String? title,
    int capacity = 6,
  }) async {
    final point = _points.firstWhere((p) => p.id == meetingPointId);
    final plan = PlanDetail(
      id: 'mine${_hosted.length}',
      title: (title ?? '').trim().isEmpty ? activity : title!.trim(),
      activity: activity,
      host: 'You',
      place: point.name,
      address: point.address,
      startsAt: startsAt,
      endsAt: endsAt,
      spotsLeft: capacity - 1,
      yourStatus: 'HOST',
      going: const ['You'],
    );
    _hosted.add(plan);
    pendingRequests[plan.id] = [
      const JoinRequest(
        handle: 'h1',
        firstName: 'Meera',
        sharedContext: 'You\'re both from Kerala',
      ),
    ];
    return plan;
  }
}
