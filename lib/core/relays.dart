import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// One story in a Story Relay: public stories that answered one another, in order.
class RelayLink {
  const RelayLink({
    required this.momentId,
    required this.firstName,
    required this.position,
    this.activity,
    this.previewUrl,
    this.mine = false,
    this.spotlit = false,
  });

  final String momentId;
  final String firstName;
  final int position;
  final String? activity;
  final String? previewUrl;
  final bool mine;

  /// The story's owner highlighted this answer, and its author agreed.
  final bool spotlit;

  /// From RelayLink.
  factory RelayLink.fromJson(Map<String, dynamic> j) => RelayLink(
    momentId: j['momentId'] as String,
    firstName: j['firstName'] as String? ?? '',
    position: (j['position'] as num?)?.toInt() ?? 0,
    activity: j['activity'] as String?,
    previewUrl: j['previewUrl'] as String?,
    mine: j['mine'] as bool? ?? false,
    spotlit: j['spotlit'] as bool? ?? false,
  );
}

class Relay {
  const Relay({required this.links, required this.open, this.activity});

  /// The links the viewer may see, root first (spotlit answers lead, as the server orders them).
  final List<RelayLink> links;

  /// Still taking answers (a relay is capped in length).
  final bool open;
  final String? activity;

  /// The story that started it, when the viewer may see it.
  RelayLink? get root => links.isEmpty ? null : links.first;

  /// From RelayView.
  factory Relay.fromJson(Map<String, dynamic> j) => Relay(
    links: [
      for (final l in (j['links'] as List? ?? const []))
        RelayLink.fromJson((l as Map).cast<String, dynamic>()),
    ],
    open: j['open'] as bool? ?? false,
    activity: j['activity'] as String?,
  );
}

/// A Spotlight request: the story's owner asks to highlight your answer. You choose; either side can withdraw.
class SpotlightRequest {
  const SpotlightRequest({
    required this.id,
    required this.withFirstName,
    required this.storyMomentId,
    required this.answerMomentId,
  });

  final String id;
  final String withFirstName;
  final String storyMomentId;
  final String answerMomentId;

  /// From SpotlightView.
  factory SpotlightRequest.fromJson(Map<String, dynamic> j) => SpotlightRequest(
    id: j['id'] as String,
    withFirstName: j['withFirstName'] as String? ?? '',
    storyMomentId: j['storyMomentId'] as String? ?? '',
    answerMomentId: j['answerMomentId'] as String? ?? '',
  );
}

abstract interface class RelayRepository {
  Future<Relay> relay(String momentId);

  /// Answers a public story with your own (words, public for a day). Throws [LocationRequired] until the area
  /// is shared.
  Future<void> answer(String momentId, String caption);

  /// As the story's owner: ask to spotlight an answer (at most 3 per story).
  Future<void> proposeSpotlight(String storyMomentId, String answerMomentId);

  /// Requests to spotlight your answers.
  Future<List<SpotlightRequest>> spotlightRequests();

  Future<void> decideSpotlight(String spotlightId, {required bool accept});
}

class ApiRelays implements RelayRepository {
  ApiRelays(this.api);

  final ApiClient api;

  @override
  Future<Relay> relay(String momentId) async => Relay.fromJson(
    await api.get('/moments/$momentId/relay') as Map<String, dynamic>,
  );

  @override
  Future<void> answer(String momentId, String caption) async {
    try {
      await api.post(
        '/moments',
        body: {
          'kind': 'TEXT',
          'caption': caption.trim(),
          'shareScope': 'PUBLIC_DISCOVERY',
          'replyToMomentId': momentId,
        },
      );
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      rethrow;
    }
  }

  @override
  Future<void> proposeSpotlight(String storyMomentId, String answerMomentId) =>
      api.post(
        '/moments/$storyMomentId/spotlights',
        body: {'answerMomentId': answerMomentId},
      );

  @override
  Future<List<SpotlightRequest>> spotlightRequests() async => [
    for (final s
        in (await api.get('/spotlights/requests') as List)
            .cast<Map<String, dynamic>>())
      SpotlightRequest.fromJson(s),
  ];

  @override
  Future<void> decideSpotlight(String spotlightId, {required bool accept}) =>
      api.post('/spotlights/$spotlightId/${accept ? 'accept' : 'decline'}');
}

class FakeRelays implements RelayRepository {
  /// Answers added in this session; the demo has one relay, so every answer joins it.
  final _answers = <RelayLink>[];
  final proposed = <(String, String)>[];
  final _requests = <SpotlightRequest>[
    const SpotlightRequest(
      id: 'sp1',
      withFirstName: 'Ananya',
      storyMomentId: 'm1',
      answerMomentId: 'mine1',
    ),
  ];

  @override
  Future<Relay> relay(String momentId) async {
    final added = _answers;
    return Relay(
      open: true,
      activity: 'sunrise',
      links: [
        RelayLink(
          momentId: momentId,
          firstName: 'Ananya',
          position: 0,
          activity: 'sunrise',
        ),
        const RelayLink(
          momentId: 'r2',
          firstName: 'Kabir',
          position: 1,
          activity: 'sunrise',
          spotlit: true,
        ),
        ...added,
      ],
    );
  }

  @override
  Future<void> answer(String momentId, String caption) async {
    _answers.add(
      RelayLink(
        momentId: 'mine${_answers.length}',
        firstName: 'You',
        position: 2 + _answers.length,
        mine: true,
      ),
    );
  }

  @override
  Future<void> proposeSpotlight(
    String storyMomentId,
    String answerMomentId,
  ) async => proposed.add((storyMomentId, answerMomentId));

  @override
  Future<List<SpotlightRequest>> spotlightRequests() async =>
      List.of(_requests);

  @override
  Future<void> decideSpotlight(String spotlightId, {required bool accept}) async =>
      _requests.removeWhere((r) => r.id == spotlightId);
}
