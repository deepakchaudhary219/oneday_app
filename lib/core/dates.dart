import 'network/api_client.dart';

/// What both people may say after a date. Only answers both gave are ever revealed; the safety ones stay private.
enum DebriefAnswer {
  goodTime('HAD_A_GOOD_TIME', 'I had a good time'),
  conversation('GREAT_CONVERSATION', 'Great conversation'),
  meetAgain('WANT_TO_MEET_AGAIN', 'I\'d like to meet again'),
  feltSafe('FELT_SAFE', 'I felt safe'),
  feltRespected('FELT_RESPECTED', 'I felt respected');

  const DebriefAnswer(this.api, this.label);

  final String api;
  final String label;
}

/// A date between two Connections (Date Mode), from the signed-in person's side.
class DatePlan {
  const DatePlan({
    required this.id,
    required this.connectionId,
    required this.partner,
    required this.place,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.youProposed = false,
    this.emergencyNumber = '112',
    this.locationWindowOpen = false,
    this.sharing = false,
    this.partnerSharing = false,
    this.trustedContact,
    this.homeSafe = false,
    this.debriefSubmitted = false,
    this.partnerLat,
    this.partnerLon,
    this.partnerAt,
  });

  final String id;
  final String connectionId;
  final String partner;
  final String place;
  final DateTime startsAt;
  final DateTime endsAt;

  /// `PROPOSED`, `CONFIRMED`, `ENDED`, `CANCELLED`, `DECLINED` or `EXPIRED`.
  final String status;
  final bool youProposed;
  final String emergencyNumber;

  /// Exact location can flow only inside the time box (from 30 minutes before the start).
  final bool locationWindowOpen;
  final bool sharing;
  final bool partnerSharing;

  /// The trusted contact's name, when one is set.
  final String? trustedContact;
  final bool homeSafe;
  final bool debriefSubmitted;

  /// The partner's last shared position: only while both share, inside the time box.
  final double? partnerLat;
  final double? partnerLon;
  final DateTime? partnerAt;

  /// This phone should be sending its position.
  bool get shouldSend => confirmed && sharing && locationWindowOpen;

  bool get proposed => status == 'PROPOSED';

  bool get confirmed => status == 'CONFIRMED';

  bool get ended => status == 'ENDED';

  /// From DateView.
  factory DatePlan.fromJson(Map<String, dynamic> j) {
    final you = (j['you'] as Map?)?.cast<String, dynamic>() ?? const {};
    final point = (j['meetingPoint'] as Map?)?.cast<String, dynamic>();
    final contact = you['trustedContact'] as String?;
    final position = (j['partnerLocation'] as Map?)?.cast<String, dynamic>();
    return DatePlan(
      id: j['id'] as String,
      connectionId: j['connectionId'] as String? ?? '',
      partner: j['partnerFirstName'] as String? ?? '',
      place:
          (j['placeName'] as String?) ?? (point?['name'] as String?) ?? 'A place',
      startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
      endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
      status: j['status'] as String? ?? 'PROPOSED',
      youProposed: j['youProposed'] as bool? ?? false,
      emergencyNumber: j['emergencyNumber'] as String? ?? '112',
      locationWindowOpen: j['locationWindowOpen'] as bool? ?? false,
      sharing: you['sharingLocation'] as bool? ?? false,
      partnerSharing: j['partnerSharing'] as bool? ?? false,
      trustedContact: contact == null || contact.isEmpty ? null : contact,
      homeSafe: you['homeSafe'] as bool? ?? false,
      debriefSubmitted: you['debriefSubmitted'] as bool? ?? false,
      partnerLat: (position?['lat'] as num?)?.toDouble(),
      partnerLon: (position?['lon'] as num?)?.toDouble(),
      partnerAt: position?['at'] == null
          ? null
          : DateTime.parse(position!['at'] as String).toLocal(),
    );
  }
}

/// The answer to a check-in or an SOS: what the server did and the number to call.
class SafetyReply {
  const SafetyReply({
    required this.message,
    required this.emergencyNumber,
    this.contactAlerted = false,
  });

  final String message;
  final String emergencyNumber;
  final bool contactAlerted;

  /// From CheckInView.
  factory SafetyReply.fromJson(Map<String, dynamic> j) => SafetyReply(
    message: j['message'] as String? ?? '',
    emergencyNumber: j['emergencyNumber'] as String? ?? '112',
    contactAlerted: j['trustedContactAlerted'] as bool? ?? false,
  );
}

abstract interface class DatesRepository {
  Future<List<DatePlan>> list();

  Future<DatePlan> propose({
    required String connectionId,
    required String placeName,
    required DateTime startsAt,
    required DateTime endsAt,
  });

  Future<DatePlan> accept(String dateId);

  Future<DatePlan> decline(String dateId);

  Future<DatePlan> cancel(String dateId);

  /// Exact location flows only while both share, and only inside the time box.
  Future<DatePlan> setSharing(String dateId, {required bool enabled});

  /// Texts the contact a private live link. Returns whether the text went out.
  Future<bool> setTrustedContact(
    String dateId, {
    required String phone,
    String? name,
  });

  /// "Going OK?": [needHelp] alerts the trusted contact and the safety desk.
  Future<SafetyReply> checkIn(String dateId, {bool needHelp = false});

  /// One tap: alerts the safety desk and the trusted contact. Never shown to the other person.
  Future<SafetyReply> sos(String dateId);

  /// "Home safe": the date ends and location stops.
  Future<DatePlan> end(String dateId);

  /// This phone's position, while both share and inside the time box (about once a minute).
  Future<DatePlan> sendPosition(String dateId, double lat, double lon);

  /// Returns the server's line (what you both felt, once both have answered).
  Future<String> debrief(String dateId, Set<DebriefAnswer> answers);
}

class ApiDates implements DatesRepository {
  ApiDates(this.api);

  final ApiClient api;

  DatePlan _date(dynamic json) => DatePlan.fromJson(json as Map<String, dynamic>);

  @override
  Future<List<DatePlan>> list() async => [
    for (final d in (await api.get('/dates') as List).cast<Map<String, dynamic>>())
      DatePlan.fromJson(d),
  ];

  @override
  Future<DatePlan> propose({
    required String connectionId,
    required String placeName,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async => _date(
    await api.post(
      '/dates',
      body: {
        'connectionId': connectionId,
        'placeName': placeName.trim(),
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<DatePlan> accept(String dateId) async =>
      _date(await api.post('/dates/$dateId/accept'));

  @override
  Future<DatePlan> decline(String dateId) async =>
      _date(await api.post('/dates/$dateId/decline'));

  @override
  Future<DatePlan> cancel(String dateId) async =>
      _date(await api.post('/dates/$dateId/cancel'));

  @override
  Future<DatePlan> setSharing(String dateId, {required bool enabled}) async =>
      _date(await api.put('/dates/$dateId/sharing', body: {'enabled': enabled}));

  @override
  Future<bool> setTrustedContact(
    String dateId, {
    required String phone,
    String? name,
  }) async {
    final label = name?.trim() ?? '';
    final json = await api.put(
      '/dates/$dateId/trusted-contact',
      body: {'phone': phone.trim(), if (label.isNotEmpty) 'name': label},
    );
    return json is Map && json['texted'] == true;
  }

  @override
  Future<SafetyReply> checkIn(String dateId, {bool needHelp = false}) async =>
      SafetyReply.fromJson(
        await api.post('/dates/$dateId/check-in', body: {'needHelp': needHelp})
            as Map<String, dynamic>,
      );

  @override
  Future<SafetyReply> sos(String dateId) async => SafetyReply.fromJson(
    await api.post('/dates/$dateId/sos') as Map<String, dynamic>,
  );

  @override
  Future<DatePlan> end(String dateId) async =>
      _date(await api.post('/dates/$dateId/end'));

  @override
  Future<DatePlan> sendPosition(String dateId, double lat, double lon) async =>
      _date(
        await api.put('/dates/$dateId/location', body: {'lat': lat, 'lon': lon}),
      );

  @override
  Future<String> debrief(String dateId, Set<DebriefAnswer> answers) async {
    final json = await api.post(
      '/dates/$dateId/debrief',
      body: {
        'answers': [for (final a in answers) a.api],
      },
    );
    return (json is Map ? json['message'] as String? : null) ??
        'Thanks. Your answers are saved.';
  }
}

/// Demo mode: one date that moves through its states as the buttons are used.
class FakeDates implements DatesRepository {
  FakeDates({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final now = _clock();
    _dates.add(
      DatePlan(
        id: 'd1',
        connectionId: 'c1',
        partner: 'Riya',
        place: 'Third Wave Coffee, Koramangala',
        startsAt: now.add(const Duration(hours: 3)),
        endsAt: now.add(const Duration(hours: 5)),
        status: 'PROPOSED',
      ),
    );
  }

  final DateTime Function() _clock;
  final _dates = <DatePlan>[];
  bool sosRaised = false;

  DatePlan _update(
    String id, {
    String? status,
    bool? sharing,
    String? trustedContact,
    bool? homeSafe,
    bool? debriefSubmitted,
  }) {
    final i = _dates.indexWhere((d) => d.id == id);
    final d = _dates[i];
    return _dates[i] = DatePlan(
      id: d.id,
      connectionId: d.connectionId,
      partner: d.partner,
      place: d.place,
      startsAt: d.startsAt,
      endsAt: d.endsAt,
      status: status ?? d.status,
      youProposed: d.youProposed,
      emergencyNumber: d.emergencyNumber,
      locationWindowOpen: (status ?? d.status) == 'CONFIRMED',
      sharing: sharing ?? d.sharing,
      partnerSharing: d.partnerSharing,
      trustedContact: trustedContact ?? d.trustedContact,
      homeSafe: homeSafe ?? d.homeSafe,
      debriefSubmitted: debriefSubmitted ?? d.debriefSubmitted,
    );
  }

  @override
  Future<List<DatePlan>> list() async => List.of(_dates);

  @override
  Future<DatePlan> propose({
    required String connectionId,
    required String placeName,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final date = DatePlan(
      id: 'd${_dates.length + 1}',
      connectionId: connectionId,
      partner: 'Your connection',
      place: placeName,
      startsAt: startsAt,
      endsAt: endsAt,
      status: 'PROPOSED',
      youProposed: true,
    );
    _dates.insert(0, date);
    return date;
  }

  @override
  Future<DatePlan> accept(String dateId) async =>
      _update(dateId, status: 'CONFIRMED');

  @override
  Future<DatePlan> decline(String dateId) async =>
      _update(dateId, status: 'DECLINED');

  @override
  Future<DatePlan> cancel(String dateId) async =>
      _update(dateId, status: 'CANCELLED');

  @override
  Future<DatePlan> setSharing(String dateId, {required bool enabled}) async =>
      _update(dateId, sharing: enabled);

  @override
  Future<bool> setTrustedContact(
    String dateId, {
    required String phone,
    String? name,
  }) async {
    _update(dateId, trustedContact: (name ?? '').trim().isEmpty ? phone : name);
    return true;
  }

  @override
  Future<SafetyReply> checkIn(String dateId, {bool needHelp = false}) async =>
      SafetyReply(
        message: needHelp
            ? 'We\'ve alerted your trusted contact and our safety team.'
            : 'Glad it\'s going well.',
        emergencyNumber: '112',
        contactAlerted: needHelp,
      );

  @override
  Future<SafetyReply> sos(String dateId) async {
    sosRaised = true;
    return const SafetyReply(
      message: 'Our safety team has been alerted. Call 112 now if you\'re in danger.',
      emergencyNumber: '112',
      contactAlerted: true,
    );
  }

  @override
  Future<DatePlan> end(String dateId) async =>
      _update(dateId, status: 'ENDED', sharing: false, homeSafe: true);

  final sentPositions = <(String, double, double)>[];

  @override
  Future<DatePlan> sendPosition(String dateId, double lat, double lon) async {
    sentPositions.add((dateId, lat, lon));
    return _dates.firstWhere((d) => d.id == dateId);
  }

  @override
  Future<String> debrief(String dateId, Set<DebriefAnswer> answers) async {
    _update(dateId, debriefSubmitted: true);
    return 'Thanks. If you both felt the same about something, you\'ll both see it.';
  }
}
