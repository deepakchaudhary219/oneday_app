import 'location.dart';
import 'models.dart';
import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// The repositories backed by the OneDay API. They map JSON through the models and the backend's error codes
/// into domain exceptions ([LocationRequired], [EmpathyCheck]); everything else surfaces as [ApiError].
class ApiData
    implements
        NearbyRepository,
        SignalsRepository,
        ChatRepository,
        StoryRepository,
        ProfileRepository {
  ApiData(this.api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ApiClient api;
  final DateTime Function() _clock;

  @override
  Future<List<NearbyMoment>> nearby({String? activity}) async {
    try {
      final json = await api.get(
        '/discover/constellation',
        query: {'scope': 'RADIUS', 'activity': activity},
      ) as Map<String, dynamic>;
      return [
        for (final n in (json['nodes'] as List).cast<Map<String, dynamic>>())
          NearbyMoment.fromJson(n),
      ];
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      rethrow;
    }
  }

  @override
  Future<SignalBudget> budget() async => SignalBudget.fromJson(
    await api.get('/signals/budget') as Map<String, dynamic>,
  );

  @override
  Future<void> sendSignal(String momentId, SignalReaction reaction) => api.post(
    '/signals',
    body: {'momentId': momentId, 'reaction': reaction.api},
  );

  @override
  Future<List<IncomingSignal>> pending() async {
    final json = await api.get('/signals/digest') as Map<String, dynamic>;
    final now = _clock();
    return [
      for (final s in (json['signals'] as List).cast<Map<String, dynamic>>())
        IncomingSignal.fromJson(s, now),
    ];
  }

  @override
  Future<String> reveal(String signalId) async {
    final json =
        await api.post('/signals/$signalId/reveal') as Map<String, dynamic>;
    return json['conversationId'] as String;
  }

  @override
  Future<void> letPass(String signalId) => api.post('/signals/$signalId/pass');

  @override
  Future<List<Conversation>> conversations() async {
    final list = (await api.get('/connections') as List)
        .cast<Map<String, dynamic>>();
    return [for (final c in list) Conversation.fromJson(c)];
  }

  @override
  Future<List<ChatMessage>> history(String conversationId) async {
    final list = (await api.get(
      '/conversations/$conversationId/messages',
      query: {'limit': 50},
    ) as List).cast<Map<String, dynamic>>();
    // The server pages newest first; the thread reads oldest first.
    return [for (final m in list.reversed) ChatMessage.fromJson(m)];
  }

  @override
  Future<ChatMessage> send(
    String conversationId,
    String body, {
    bool sendAnyway = false,
  }) async {
    try {
      final json = await api.post(
        '/conversations/$conversationId/messages',
        body: {'body': body, 'sendAnyway': sendAnyway},
      );
      return ChatMessage.fromJson(json as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.code == 'EMPATHY_CHECK') throw EmpathyCheck(e.detail);
      rethrow;
    }
  }

  @override
  Future<MyProfile> me() async =>
      MyProfile.fromJson(await api.get('/profile/me') as Map<String, dynamic>);

  @override
  Future<List<Story>> friendsStories() async {
    final list = (await api.get('/moments/friends') as List)
        .cast<Map<String, dynamic>>();
    final now = _clock();
    return [for (final s in list) Story.fromJson(s, now)];
  }
}

/// Shares the phone's current area (foreground only); the server snaps it to a cell.
abstract interface class LocationShare {
  Future<bool> share();
}

class ApiLocationShare implements LocationShare {
  ApiLocationShare(this.api, this.source);

  final ApiClient api;
  final LocationSource source;

  @override
  Future<bool> share() async {
    final here = await source.current();
    if (here == null) return false;
    await api.put('/location', body: {'lat': here.lat, 'lon': here.lon});
    return true;
  }
}

class FakeLocationShare implements LocationShare {
  @override
  Future<bool> share() async => true;
}
