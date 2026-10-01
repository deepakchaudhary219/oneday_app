/// Domain models. They mirror the backend contract (contract/openapi.json) and know how to read it, so the API
/// repositories stay thin and the screens never see JSON.
library;

/// Nearby moment at Layer 0 (ambient): first name, activity and a distance label, never more.
class NearbyMoment {
  const NearbyMoment({
    required this.id,
    required this.firstName,
    required this.activity,
    required this.distance,
    required this.seed,
    this.postedAgo,
    this.liveCapture = true,
    this.prompt,
    this.previewUrl,
    this.why,
  });

  /// The moment id (what a Signal answers).
  final String id;
  final String firstName;
  final String activity;

  /// A coarse, privacy-safe label from the server ("Under 1 km", "In your city"); never computed on the phone.
  final String distance;
  final int seed;
  final String? postedAgo;
  final bool liveCapture;

  /// Set when the moment answers Today's Prompt.
  final String? prompt;
  final String? previewUrl;

  /// "Why you see this": shared roots, languages or activity.
  final String? why;

  /// From ConstellationNode.
  factory NearbyMoment.fromJson(Map<String, dynamic> j) => NearbyMoment(
    id: j['nodeId'] as String,
    firstName: j['firstName'] as String? ?? '',
    activity: j['activity'] as String? ?? '',
    distance: j['distance'] as String? ?? '',
    seed: (j['nodeId'] as String).hashCode,
    liveCapture: j['liveCaptured'] as bool? ?? false,
    previewUrl: j['previewUrl'] as String?,
    why: j['whyYouSeeThis'] as String?,
  );
}

/// Signal reactions, exactly the backend's set: no free text before a mutual reveal.
enum SignalReaction {
  resonates('RESONATES', 'Resonates', '✨'),
  madeMeSmile('MADE_ME_SMILE', 'Made me smile', '😊'),
  wantToKnowMore('WANT_TO_KNOW_MORE', 'Want to know more', '👋'),
  sameHere('SAME_HERE', 'Same here', '🙌');

  const SignalReaction(this.api, this.label, this.emoji);

  final String api;
  final String label;
  final String emoji;

  static SignalReaction fromApi(String? value) => values.firstWhere(
    (r) => r.api == value,
    orElse: () => SignalReaction.resonates,
  );
}

class SignalBudget {
  const SignalBudget({
    required this.remaining,
    required this.daily,
    this.nextFreesAt,
  });

  final int remaining;
  final int daily;

  /// Set only when none are left.
  final DateTime? nextFreesAt;

  factory SignalBudget.fromJson(Map<String, dynamic> j) => SignalBudget(
    remaining: (j['remaining'] as num).toInt(),
    daily: (j['dailyBudget'] as num).toInt(),
    nextFreesAt: j['nextFreesAt'] == null
        ? null
        : DateTime.parse(j['nextFreesAt'] as String),
  );
}

/// Someone who reached out (a received Signal) waiting in the 48 h Reaction Window.
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

  static const reactionWindow = Duration(hours: 48);

  final String id;
  final String firstName;
  final SignalReaction reaction;
  final String activity;
  final String sharedContext;
  final String timeLeft;
  final int seed;

  /// From DigestItem.
  factory IncomingSignal.fromJson(Map<String, dynamic> j, DateTime now) {
    final received = DateTime.parse(j['receivedAt'] as String);
    return IncomingSignal(
      id: j['signalId'] as String,
      firstName: j['firstName'] as String? ?? '',
      reaction: SignalReaction.fromApi(j['reaction'] as String?),
      activity: (j['activityRef'] ?? j['aboutActivity'] ?? '') as String,
      sharedContext: j['sharedContext'] as String? ?? '',
      timeLeft: timeLeftLabel(received.add(reactionWindow).difference(now)),
      seed: (j['signalId'] as String).hashCode,
    );
  }

  /// Calm wording: stated, never ticking.
  static String timeLeftLabel(Duration left) {
    if (left.inHours >= 24) {
      return left.inHours < 48 ? '1 day left' : '${left.inDays} days left';
    }
    if (left.inHours >= 1) return '${left.inHours} hours left';
    return 'Less than an hour left';
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.firstName,
    required this.warmth,
    required this.seed,
    this.conversationId,
    this.lastMessage,
    this.lastAt,
    this.lastFromMe = false,
    this.warmthLine,
    this.unread = false,
    this.hasStory = false,
    this.encrypted = false,
  });

  /// The connection id.
  final String id;
  final String? conversationId;
  final String firstName;
  final String? lastMessage;
  final DateTime? lastAt;
  final bool lastFromMe;

  /// Connection Warmth 0-3 (never a streak count).
  final int warmth;

  /// The server's warmth line or conversation starter, shown when there's no message yet.
  final String? warmthLine;
  final int seed;
  final bool unread;
  final bool hasStory;
  final bool encrypted;

  String get preview => lastMessage == null
      ? (warmthLine ?? 'Say hi 👋')
      : (lastFromMe ? 'You: $lastMessage' : lastMessage!);

  /// From ConnectionView.
  factory Conversation.fromJson(Map<String, dynamic> j) {
    final warmth = j['warmth'] as Map<String, dynamic>?;
    final level = switch (warmth?['level']) {
      'GLOWING' => 3,
      'WARM' => 2,
      'KINDLING' => 1,
      _ => 0,
    };
    final last = j['lastMessage'] as String?;
    return Conversation(
      id: j['id'] as String,
      conversationId: j['conversationId'] as String?,
      firstName: j['displayName'] as String? ?? '',
      lastMessage: last,
      lastAt: j['lastMessageAt'] == null
          ? null
          : DateTime.parse(j['lastMessageAt'] as String),
      lastFromMe: j['lastFromMe'] as bool? ?? false,
      warmth: level,
      warmthLine: (warmth?['starter'] ?? warmth?['line']) as String?,
      seed: (j['id'] as String).hashCode,
      unread: last != null && !(j['lastFromMe'] as bool? ?? false),
      encrypted: last == 'Encrypted message',
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.mine,
    required this.body,
    required this.sentAt,
    this.pending = false,
    this.pacingHint,
    this.concern,
  });

  final String id;
  final bool mine;
  final String body;
  final DateTime sentAt;

  /// Optimistic send: shown at once, confirmed when the server answers.
  final bool pending;

  /// Pacing Guardian's private note to the sender.
  final String? pacingHint;

  /// Empathy Mirror's "Does this bother you?" for the recipient.
  final String? concern;

  ChatMessage confirmed() => ChatMessage(
    id: id,
    mine: mine,
    body: body,
    sentAt: sentAt,
    pacingHint: pacingHint,
  );

  /// From MessageView.
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    mine: j['mine'] as bool? ?? false,
    body:
        (j['body'] as String?) ??
        (j['encrypted'] == true ? '🔒 Encrypted message' : ''),
    sentAt: DateTime.parse(j['sentAt'] as String),
    pacingHint: j['pacingHint'] as String?,
    concern: (j['concern'] as Map<String, dynamic>?)?['question'] as String?,
  );
}

/// A person's live stories (one ring).
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

  /// From FriendStories.
  factory Story.fromJson(Map<String, dynamic> j, DateTime now) {
    final moments = (j['moments'] as List).cast<Map<String, dynamic>>();
    final name = j['firstName'] as String? ?? '';
    return Story(
      id: moments.isEmpty ? name : moments.first['id'] as String,
      firstName: (j['mine'] as bool? ?? false) ? 'You' : name,
      mine: j['mine'] as bool? ?? false,
      seed: name.hashCode,
      frames: [for (final m in moments) StoryFrame.fromJson(m, now)],
    );
  }
}

class StoryFrame {
  const StoryFrame({
    required this.seed,
    required this.postedAgo,
    this.caption,
    this.activity,
    this.mediaUrl,
  });

  final int seed;
  final String postedAgo;
  final String? caption;
  final String? activity;
  final String? mediaUrl;

  /// From MomentView.
  factory StoryFrame.fromJson(Map<String, dynamic> j, DateTime now) =>
      StoryFrame(
        seed: (j['id'] as String).hashCode,
        postedAgo: j['postedAt'] == null
            ? ''
            : ago(now.difference(DateTime.parse(j['postedAt'] as String))),
        caption: j['caption'] as String?,
        activity: j['activityTag'] as String?,
        mediaUrl: j['mediaUrl'] as String?,
      );
}

/// Compact relative time ("3m", "2h", "Yesterday").
String ago(Duration d) {
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays == 1) return 'Yesterday';
  return '${d.inDays}d';
}

/// The signed-in person's own profile (GET /profile/me), as much of it as the Me tab shows.
class MyProfile {
  const MyProfile({
    required this.displayName,
    this.homeRegion,
    this.verificationStatus = 'UNVERIFIED',
  });

  factory MyProfile.fromJson(Map<String, dynamic> j) => MyProfile(
    displayName: j['displayName'] as String? ?? '',
    homeRegion: j['homeRegion'] as String?,
    verificationStatus: j['verificationStatus'] as String? ?? 'UNVERIFIED',
  );

  final String displayName;
  final String? homeRegion;
  final String verificationStatus;

  bool get verified => verificationStatus == 'VERIFIED';
}
