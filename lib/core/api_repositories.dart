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
  ApiData(
    this.api, {
    DateTime Function()? clock,
    this.pollEvery = const Duration(milliseconds: 700),
    this.pollLimit = 40,
  }) : _clock = clock ?? DateTime.now;

  /// How often, and how many times, to ask whether an upload has been processed (about half a minute in all).
  final Duration pollEvery;
  final int pollLimit;

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
  Future<String?> balanceNudge(String conversationId) async {
    final json =
        await api.get('/conversations/$conversationId/balance')
            as Map<String, dynamic>;
    return json['state'] == 'NUDGE' ? json['message'] as String? : null;
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

  @override
  Future<String> upload(Capture capture) async {
    final ticket = await api.post(
      '/media/uploads',
      body: {
        'kind': capture.video ? 'VIDEO' : 'PHOTO',
        'contentType': capture.contentType,
        'sizeBytes': capture.bytes.length,
      },
    ) as Map<String, dynamic>;
    final mediaRef = ticket['mediaRef'] as String;
    await api.upload(
      ticket['uploadUrl'] as String,
      capture.bytes,
      method: ticket['method'] as String? ?? 'PUT',
      headers: {
        'Content-Type': capture.contentType,
        for (final h in (ticket['headers'] as Map? ?? const {}).entries)
          '${h.key}': '${h.value}',
      },
    );
    var state = await api.post(
      '/media/uploads/complete',
      body: {'mediaRef': mediaRef},
    ) as Map<String, dynamic>;
    // The server strips metadata (and transcodes video) before anything can be attached.
    for (var asked = 0; ; asked++) {
      switch (state['status']) {
        case 'READY':
          return mediaRef;
        case 'REJECTED':
          throw MediaRejected(
            state['rejectReason'] as String? ??
                "That couldn't be used. Try another shot.",
          );
      }
      if (asked >= pollLimit) {
        throw const ApiError(
          status: 0,
          code: 'MEDIA_NOT_READY',
          detail: 'Still preparing your story. Try again in a moment.',
        );
      }
      await Future<void>.delayed(pollEvery);
      state = await api.get(
        '/media/uploads/status',
        query: {'mediaRef': mediaRef},
      ) as Map<String, dynamic>;
    }
  }

  @override
  Future<void> publish(StoryDraft draft) async {
    final caption = draft.caption?.trim() ?? '';
    final activity = draft.activity?.trim() ?? '';
    if (draft.mediaRef == null && caption.isEmpty) {
      throw const CaptionRequired();
    }
    try {
      await api.post(
        '/moments',
        body: {
          'kind': draft.mediaRef == null
              ? 'TEXT'
              : (draft.video ? 'VIDEO' : 'PHOTO'),
          'shareScope': draft.scope.api,
          if (draft.mediaRef != null) 'mediaRef': draft.mediaRef,
          // Media only ever comes from the in-app camera, which is what "live" means to the server.
          if (draft.mediaRef != null) 'capturedLive': true,
          if (caption.isNotEmpty) 'caption': caption,
          if (activity.isNotEmpty) 'activityTag': activity,
        },
      );
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      if (e.code == 'CAPTION_REQUIRED') throw const CaptionRequired();
      rethrow;
    }
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
