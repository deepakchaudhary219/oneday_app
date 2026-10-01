/// Domain models shared by features. They mirror the backend's API views (docs/api/openapi.json in the backend
/// repository) closely, so swapping the fake repositories for the generated client is a mapping, not a redesign.
library;

/// How far away someone is, always a band: the backend never exposes a distance precise enough to locate anyone.
enum DistanceBand {
  veryClose('Very close'),
  walkable('Walking distance'),
  nearby('Nearby'),
  acrossTown('Across town');

  const DistanceBand(this.label);

  final String label;
}

/// A nearby public moment at Layer 0 (ambient): first name, activity, distance band, never more.
class NearbyMoment {
  const NearbyMoment({
    required this.id,
    required this.firstName,
    required this.activity,
    required this.band,
    required this.postedAgo,
    required this.seed,
    this.liveCapture = true,
    this.prompt,
  });

  final String id;
  final String firstName;
  final String activity;
  final DistanceBand band;
  final String postedAgo;
  final int seed;
  final bool liveCapture;

  /// Set when the moment answers Today's Prompt.
  final String? prompt;
}

/// The Signal reactions: no free text before a mutual reveal (approach cost, women's safety).
enum SignalReaction {
  madeMeSmile('Made me smile', '😊'),
  sameHere('Same here', '🙌'),
  wantToJoin('Want to join', '👋'),
  teachMe('Teach me', '✨');

  const SignalReaction(this.label, this.emoji);

  final String label;
  final String emoji;
}

/// Someone who reached out (a received Signal) waiting in the Reaction Window.
class IncomingSignal {
  const IncomingSignal({
    required this.id,
    required this.firstName,
    required this.reaction,
    required this.activity,
    required this.sharedContext,
    required this.timeLeft,
    required this.seed,
  });

  final String id;
  final String firstName;
  final SignalReaction reaction;
  final String activity;
  final String sharedContext;
  final String timeLeft;
  final int seed;
}

class Conversation {
  const Conversation({
    required this.id,
    required this.firstName,
    required this.lastMessage,
    required this.when,
    required this.warmth,
    required this.seed,
    this.unread = false,
    this.hasStory = false,
    this.encrypted = true,
  });

  final String id;
  final String firstName;
  final String lastMessage;
  final String when;

  /// Connection Warmth 0-3 (never a streak count).
  final int warmth;
  final int seed;
  final bool unread;
  final bool hasStory;
  final bool encrypted;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.mine,
    required this.body,
    required this.sentAt,
    this.pending = false,
  });

  final String id;
  final bool mine;
  final String body;
  final DateTime sentAt;

  /// Optimistic send: shown at once, confirmed when the server answers.
  final bool pending;

  ChatMessage confirmed() =>
      ChatMessage(id: id, mine: mine, body: body, sentAt: sentAt);
}

/// A story (one or more frames) by someone you're connected to, or your own.
class Story {
  const Story({
    required this.id,
    required this.firstName,
    required this.frames,
    required this.seed,
    this.mine = false,
  });

  final String id;
  final String firstName;
  final List<StoryFrame> frames;
  final int seed;
  final bool mine;
}

class StoryFrame {
  const StoryFrame({
    required this.seed,
    required this.postedAgo,
    this.caption,
    this.activity,
  });

  final int seed;
  final String postedAgo;
  final String? caption;
  final String? activity;
}
