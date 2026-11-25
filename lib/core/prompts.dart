import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// Someone nearby who answered today's prompt: Layer 0, a first name and an activity.
class PromptAnswer {
  const PromptAnswer({
    required this.momentId,
    required this.firstName,
    this.activity,
    this.previewUrl,
  });

  final String momentId;
  final String firstName;
  final String? activity;
  final String? previewUrl;

  factory PromptAnswer.fromJson(Map<String, dynamic> j) => PromptAnswer(
    momentId: j['momentId'] as String? ?? '',
    firstName: j['firstName'] as String? ?? '',
    activity: j['activity'] as String?,
    previewUrl: j['previewUrl'] as String?,
  );
}

/// One local prompt a day. Nearby answers unlock once you've answered publicly yourself.
class TodaysPrompt {
  const TodaysPrompt({
    required this.promptKey,
    required this.text,
    this.answeredByYou = false,
    this.unlocked = false,
    this.answeredNearby,
    this.message,
    this.festival,
    this.answers = const [],
  });

  final String promptKey;
  final String text;
  final bool answeredByYou;
  final bool unlocked;

  /// A truthful teaser in the server's words ("A few people nearby answered").
  final String? answeredNearby;
  final String? message;
  final String? festival;
  final List<PromptAnswer> answers;

  /// From TodayView.
  factory TodaysPrompt.fromJson(Map<String, dynamic> j) => TodaysPrompt(
    promptKey: j['promptKey'] as String? ?? '',
    text: j['text'] as String? ?? '',
    answeredByYou: j['answeredByYou'] as bool? ?? false,
    unlocked: j['unlocked'] as bool? ?? false,
    answeredNearby: j['answeredNearby'] as String?,
    message: j['message'] as String?,
    festival: j['festival'] as String?,
    answers: [
      for (final a in (j['answers'] as List? ?? const []))
        PromptAnswer.fromJson((a as Map).cast<String, dynamic>()),
    ],
  );
}

abstract interface class PromptRepository {
  Future<TodaysPrompt> today();

  /// Answers in words, as a public story for a day. Throws [LocationRequired] until the area is shared.
  Future<void> answer(String promptKey, String text);
}

class ApiPrompts implements PromptRepository {
  ApiPrompts(this.api);

  final ApiClient api;

  @override
  Future<TodaysPrompt> today() async => TodaysPrompt.fromJson(
    await api.get('/prompts/today') as Map<String, dynamic>,
  );

  @override
  Future<void> answer(String promptKey, String text) async {
    try {
      await api.post(
        '/moments',
        body: {
          'kind': 'TEXT',
          'caption': text.trim(),
          'shareScope': 'PUBLIC_DISCOVERY',
          'promptKey': promptKey,
        },
      );
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      rethrow;
    }
  }
}

class FakePrompts implements PromptRepository {
  bool _answered = false;

  @override
  Future<TodaysPrompt> today() async => TodaysPrompt(
    promptKey: 'demo-today',
    text: 'What does your street smell like at 7 am?',
    answeredByYou: _answered,
    unlocked: _answered,
    answeredNearby: 'A few people nearby answered',
    answers: _answered
        ? const [
            PromptAnswer(momentId: 'p1', firstName: 'Riya', activity: 'chai'),
            PromptAnswer(
              momentId: 'p2',
              firstName: 'Arjun',
              activity: 'filter coffee',
            ),
          ]
        : const [],
  );

  @override
  Future<void> answer(String promptKey, String text) async => _answered = true;
}
