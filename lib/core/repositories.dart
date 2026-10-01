import 'dart:async';

import 'models.dart';

/// Data access for the features. Screens see only these interfaces; the implementation is chosen in one
/// provider ([repositoryProvider]-style overrides in tests, the generated API client in production).
abstract interface class NearbyRepository {
  /// One bounded page: the backend caps results, and the UI ends with a closure card.
  Future<List<NearbyMoment>> nearby({String? activity});

  Future<int> signalsLeftToday();

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
}

abstract interface class StoryRepository {
  Future<List<Story>> friendsStories();
}

/// The Empathy Mirror said "this might land badly"; the UI shows [reflection] and offers Edit / Send anyway.
class EmpathyCheck implements Exception {
  const EmpathyCheck(this.reflection);

  final String reflection;
}
