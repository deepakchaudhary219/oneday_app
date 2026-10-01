import 'dart:async';

import 'models.dart';
import 'repositories.dart';

/// Realistic fake data with small latencies, so loading states, optimistic updates and transitions can be
/// designed and tested before the API client is wired.
class FakeData
    implements
        NearbyRepository,
        SignalsRepository,
        ChatRepository,
        StoryRepository,
        ProfileRepository {
  FakeData({this.latency = const Duration(milliseconds: 450)});

  final Duration latency;

  int _signals = 3;
  static const _dailySignals = 3;

  final _pending = <IncomingSignal>[
    const IncomingSignal(
      id: 's1',
      firstName: 'Ananya',
      reaction: SignalReaction.sameHere,
      activity: 'trek',
      sharedContext: 'You both posted from Nandi Hills this morning',
      timeLeft: '1 day left',
      seed: 10,
    ),
    const IncomingSignal(
      id: 's2',
      firstName: 'Kabir',
      reaction: SignalReaction.wantToKnowMore,
      activity: 'badminton',
      sharedContext: 'You both play badminton on weekends',
      timeLeft: '2 days left',
      seed: 29,
    ),
    const IncomingSignal(
      id: 's3',
      firstName: 'Meera',
      reaction: SignalReaction.madeMeSmile,
      activity: 'chai',
      sharedContext: 'Roots: you\'re both from Kerala',
      timeLeft: '5 hours left',
      seed: 5,
    ),
  ];

  final _messages = <String, List<ChatMessage>>{};

  Future<T> _later<T>(T value) => Future.delayed(latency, () => value);

  @override
  Future<List<NearbyMoment>> nearby({String? activity}) {
    const all = [
      NearbyMoment(
        id: 'm1',
        firstName: 'Riya',
        activity: 'sunrise trek',
        distance: '1–5 km',
        postedAgo: '12m',
        seed: 25,
        prompt: 'Best view in your city?',
        why: 'You both posted from Nandi Hills this week',
        tags: ['Speaks Kannada', 'Trekking'],
      ),
      NearbyMoment(
        id: 'm2',
        firstName: 'Arjun',
        activity: 'chess at a café',
        distance: 'Under 1 km',
        postedAgo: '25m',
        seed: 9,
        why: 'Sana vouches for Arjun',
        tags: ['Sana vouches', 'Speaks Hindi'],
      ),
      NearbyMoment(
        id: 'm3',
        firstName: 'Sana',
        activity: 'street food walk',
        distance: '5–15 km',
        postedAgo: '40m',
        seed: 13,
        prompt: 'Your comfort food?',
        why: 'Roots: you\'re both from Kerala',
        tags: ['Also from Kerala', 'Speaks Malayalam'],
      ),
      NearbyMoment(
        id: 'm4',
        firstName: 'Dev',
        activity: 'cycling in the park',
        distance: 'In your city',
        postedAgo: '1h',
        seed: 4,
        why: 'You both love cycling',
        tags: ['Cycling', 'Early riser'],
      ),
      NearbyMoment(
        id: 'm5',
        firstName: 'Ira',
        activity: 'rooftop gig',
        distance: '1–5 km',
        postedAgo: '2h',
        seed: 16,
        why: 'You\'re both into live music',
        tags: ['Live music', 'Speaks Tamil'],
      ),
    ];
    return _later(
      activity == null
          ? all
          : all.where((m) => m.activity.contains(activity)).toList(),
    );
  }

  @override
  Future<SignalBudget> budget() => _later(
    SignalBudget(
      remaining: _signals,
      daily: _dailySignals,
      nextFreesAt: _signals == 0
          ? DateTime.now().add(const Duration(hours: 9))
          : null,
    ),
  );

  @override
  Future<void> sendSignal(String momentId, SignalReaction reaction) async {
    await Future<void>.delayed(latency);
    if (_signals <= 0) throw StateError('No signals left today');
    _signals--;
  }

  @override
  Future<List<IncomingSignal>> pending() => _later(List.of(_pending));

  @override
  Future<String> reveal(String signalId) async {
    await Future<void>.delayed(latency);
    _pending.removeWhere((s) => s.id == signalId);
    return 'c-$signalId';
  }

  @override
  Future<void> letPass(String signalId) async {
    await Future<void>.delayed(latency);
    _pending.removeWhere((s) => s.id == signalId);
  }

  /// One look per person everywhere (avatar, stories, nearby): Asha (you) 2, Riya 25, Arjun 9, Sana 13, Dev 4,
  /// Ira 16, Ananya 10, Kabir 29, Meera 5, Rohan 1, Zoya 7.
  @override
  Future<List<Conversation>> conversations() {
    final now = DateTime.now();
    return _later([
      Conversation(
        id: 'c1',
        conversationId: 'c1',
        firstName: 'Riya',
        lastMessage: 'Same time Saturday? ☕',
        lastAt: now.subtract(const Duration(minutes: 2)),
        warmth: 3,
        seed: 25,
        unread: true,
        hasStory: true,
        encrypted: true,
      ),
      Conversation(
        id: 'c2',
        conversationId: 'c2',
        firstName: 'Arjun',
        lastMessage: 'That opening was wild',
        lastAt: now.subtract(const Duration(minutes: 48)),
        warmth: 2,
        seed: 9,
        unread: true,
        hasStory: true,
      ),
      Conversation(
        id: 'c5',
        conversationId: 'c5',
        firstName: 'Zoya',
        lastMessage: 'ok the playlist is ready 🎧',
        lastFromMe: true,
        lastAt: now.subtract(const Duration(hours: 3)),
        warmth: 2,
        seed: 7,
        hasStory: true,
        encrypted: true,
      ),
      Conversation(
        id: 'c3',
        conversationId: 'c3',
        firstName: 'Sana',
        lastMessage: 'sending the place 📍',
        lastFromMe: true,
        lastAt: now.subtract(const Duration(days: 1)),
        warmth: 1,
        seed: 13,
      ),
      Conversation(
        id: 'c6',
        conversationId: 'c6',
        firstName: 'Rohan',
        lastMessage: 'Cubbon park run tomorrow?',
        lastAt: now.subtract(const Duration(days: 2)),
        warmth: 1,
        seed: 1,
      ),
      const Conversation(
        id: 'c4',
        conversationId: 'c4',
        firstName: 'Dev',
        warmthLine: 'You both love cycling. Ask about their favourite route?',
        warmth: 0,
        seed: 4,
      ),
    ]);
  }

  @override
  Future<List<ChatMessage>> history(String conversationId) {
    final now = DateTime.now();
    return _later(
      _messages.putIfAbsent(
        conversationId,
        () => [
          ChatMessage(
            id: '1',
            mine: false,
            body: 'That trek photo was unreal',
            sentAt: now.subtract(const Duration(minutes: 40)),
          ),
          ChatMessage(
            id: '2',
            mine: true,
            body: 'Haha it was 5am, worth it',
            sentAt: now.subtract(const Duration(minutes: 38)),
          ),
          ChatMessage(
            id: '3',
            mine: false,
            body: 'Same time Saturday? ☕',
            sentAt: now.subtract(const Duration(minutes: 2)),
          ),
        ],
      ),
    );
  }

  static const _unkind = ['stupid', 'idiot', 'loser', 'ugly', 'shut up'];

  @override
  Future<ChatMessage> send(
    String conversationId,
    String body, {
    bool sendAnyway = false,
  }) async {
    await Future<void>.delayed(latency);
    final lower = body.toLowerCase();
    if (!sendAnyway && _unkind.any(lower.contains)) {
      throw const EmpathyCheck(
        'This might sting. Is there a kinder way to say it?',
      );
    }
    final message = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      mine: true,
      body: body,
      sentAt: DateTime.now(),
    );
    _messages.putIfAbsent(conversationId, () => []).add(message);
    return message;
  }

  @override
  Future<MyProfile> me() => _later(
    const MyProfile(
      displayName: 'Asha',
      homeRegion: 'Bengaluru',
      bio: 'Chai, sunrise treks and street food. Learning to make pottery 🏺',
    ),
  );

  @override
  Future<List<Story>> friendsStories() => _later(const [
    Story(
      id: 'st0',
      firstName: 'You',
      mine: true,
      seed: 2,
      frames: [
        StoryFrame(
          seed: 21,
          postedAgo: '3h',
          caption: 'Monsoon mornings',
          activity: 'monsoon',
        ),
      ],
    ),
    Story(
      id: 'st1',
      firstName: 'Riya',
      seed: 25,
      frames: [
        StoryFrame(
          seed: 1,
          postedAgo: '20m',
          caption: 'Made it before sunrise',
          activity: 'trek',
        ),
        StoryFrame(
          seed: 6,
          postedAgo: '18m',
          caption: 'Worth every step',
          activity: 'sunrise',
        ),
      ],
    ),
    Story(
      id: 'st2',
      firstName: 'Arjun',
      seed: 9,
      frames: [
        StoryFrame(
          seed: 2,
          postedAgo: '1h',
          caption: 'Café chess club, round 3',
          activity: 'chess at a café',
        ),
      ],
    ),
    Story(
      id: 'st4',
      firstName: 'Zoya',
      seed: 7,
      frames: [
        StoryFrame(
          seed: 12,
          postedAgo: '2h',
          caption: 'Front row 🎶',
          activity: 'gig',
        ),
        StoryFrame(
          seed: 13,
          postedAgo: '2h',
          caption: 'Encore!',
          activity: 'concert',
        ),
      ],
    ),
    Story(
      id: 'st3',
      firstName: 'Sana',
      seed: 13,
      frames: [
        StoryFrame(
          seed: 3,
          postedAgo: '4h',
          caption: 'Night market finds',
          activity: 'city night',
        ),
      ],
    ),
    Story(
      id: 'st5',
      firstName: 'Rohan',
      seed: 1,
      frames: [
        StoryFrame(
          seed: 8,
          postedAgo: '5h',
          caption: 'Goa, finally',
          activity: 'beach',
        ),
      ],
    ),
  ]);
}
