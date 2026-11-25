import 'dart:async';

import 'models.dart';

/// Data access for the features. Screens see only these interfaces; [FakeData] backs them in design/demo mode and
/// the `Api*` implementations against the backend (chosen in providers.dart from ApiConfig).
abstract interface class NearbyRepository {
  /// One bounded page: the backend caps results, and the UI ends with a closure card.
  Future<List<NearbyMoment>> nearby({String? activity});

  Future<SignalBudget> budget();

  Future<void> sendSignal(String momentId, SignalReaction reaction);
}

abstract interface class SignalsRepository {
  Future<List<IncomingSignal>> pending();

  /// Mutual Reveal: returns the new conversation id.
  Future<String> reveal(String signalId);

  /// Silent for the sender, by design.
  Future<void> letPass(String signalId);
}

abstract interface class ChatRepository {
  Future<List<Conversation>> conversations();

  Future<List<ChatMessage>> history(String conversationId);

  Future<ChatMessage> send(
    String conversationId,
    String body, {
    bool sendAnyway = false,
  });

  /// Investment Balance: a private, gentle line when the other person has been carrying the conversation
  /// ("Maybe ask them something back?"). Null when there's nothing to say.
  Future<String?> balanceNudge(String conversationId);
}

abstract interface class ProfileRepository {
  Future<MyProfile> me();
}

abstract interface class StoryRepository {
  Future<List<Story>> friendsStories();

  /// Sends a capture to storage and waits until the server has processed it (metadata stripped). Returns the
  /// media reference to put on a [StoryDraft]; it can be attached once, within 24 hours.
  Future<String> upload(Capture capture);

  /// Publishes a story for 24 hours. Throws [CaptionRequired] for a story with neither media nor words, and
  /// [LocationRequired] for a Nearby share before the area has been shared.
  Future<void> publish(StoryDraft draft);
}

/// A story without media needs some words.
class CaptionRequired implements Exception {
  const CaptionRequired();
}

/// The server refused the upload after looking at it (unreadable, too long, too large); [reason] is for people.
class MediaRejected implements Exception {
  const MediaRejected(this.reason);

  final String reason;
}

/// The Empathy Mirror said "this might land badly"; the UI shows [reflection] and offers Edit / Send anyway.
class EmpathyCheck implements Exception {
  const EmpathyCheck(this.reflection);

  final String reflection;
}

/// Nearby (seeing it, or sharing a story to it) needs the person's (coarse) location first.
class LocationRequired implements Exception {
  const LocationRequired();
}
