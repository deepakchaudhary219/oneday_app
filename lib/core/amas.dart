import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// An AMA Corridor: a verified figure answers questions for 15 to 120 minutes, open to everyone or to one
/// Roots corridor (people from one home region, wherever they live).
class Ama {
  const Ama({
    required this.id,
    required this.title,
    required this.hostName,
    required this.startsAt,
    required this.endsAt,
    required this.state,
    this.hostHandle,
    this.corridorRegion,
    this.canAsk = false,
    this.youHost = false,
  });

  final String id;
  final String title;
  final String hostName;
  final String? hostHandle;
  final DateTime startsAt;
  final DateTime endsAt;

  /// `UPCOMING`, `LIVE`, `ENDED` or `CANCELLED`.
  final String state;

  /// A home region such as `IN-KL`, or null for everyone.
  final String? corridorRegion;

  /// Questions open a day before the start; the host can't ask.
  final bool canAsk;
  final bool youHost;

  bool get live => state == 'LIVE';

  bool get upcoming => state == 'UPCOMING';

  /// From AmaView.
  factory Ama.fromJson(Map<String, dynamic> j) => Ama(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    hostName: j['hostName'] as String? ?? '',
    hostHandle: j['hostHandle'] as String?,
    startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
    endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
    state: j['state'] as String? ?? 'UPCOMING',
    corridorRegion: j['corridorRegion'] as String?,
    canAsk: j['canAsk'] as bool? ?? false,
    youHost: j['youHost'] as bool? ?? false,
  );
}

class AmaQuestion {
  const AmaQuestion({
    required this.id,
    required this.question,
    required this.askedBy,
    this.answer,
    this.mine = false,
    this.youVoted = false,
    this.votes,
    this.hidden = false,
    this.concern,
  });

  final String id;
  final String question;

  /// A first name, or "Someone from IN-KL" for an anonymous question.
  final String askedBy;
  final String? answer;
  final bool mine;
  final bool youVoted;

  /// Shown to the host only; null for everyone else.
  final int? votes;

  /// Hidden by the host or a moderator (only the host still sees it).
  final bool hidden;

  /// The Empathy Mirror's "Does this bother you?" for readers.
  final String? concern;

  /// From QuestionView.
  factory AmaQuestion.fromJson(Map<String, dynamic> j) => AmaQuestion(
    id: j['id'] as String,
    question: j['question'] as String? ?? '',
    askedBy: j['askedBy'] as String? ?? 'Someone',
    answer: j['answer'] as String?,
    mine: j['mine'] as bool? ?? false,
    youVoted: j['youVoted'] as bool? ?? false,
    votes: (j['votes'] as num?)?.toInt(),
    hidden: j['hidden'] as bool? ?? false,
    concern: (j['concern'] as Map?)?['question'] as String?,
  );
}

class AmaDetail {
  const AmaDetail({required this.ama, required this.questions});

  final Ama ama;

  /// In the server's order: votes first, then time.
  final List<AmaQuestion> questions;

  factory AmaDetail.fromJson(Map<String, dynamic> j) => AmaDetail(
    ama: Ama.fromJson((j['ama'] as Map).cast<String, dynamic>()),
    questions: [
      for (final q in (j['questions'] as List? ?? const []))
        AmaQuestion.fromJson((q as Map).cast<String, dynamic>()),
    ],
  );
}

abstract interface class AmasRepository {
  /// AMAs you can see: open to everyone, or in your Roots corridor.
  Future<List<Ama>> list();

  Future<AmaDetail> detail(String amaId);

  /// Up to 3 per person. Throws [EmpathyCheck] when the Empathy Mirror asks for a second look.
  Future<void> ask(
    String amaId,
    String question, {
    bool anonymous = false,
    bool sendAnyway = false,
  });

  Future<void> vote(String amaId, String questionId, {required bool on});

  /// Host only: 15 to 120 minutes; questions open a day before [startsAt].
  Future<Ama> schedule({
    required String title,
    required DateTime startsAt,
    int minutes = 60,
    String? corridorRegion,
  });

  /// Host only, while live.
  Future<void> answer(String amaId, String questionId, String answer);

  /// Host only.
  Future<void> hide(String amaId, String questionId);

  /// Host only, before it starts.
  Future<void> cancel(String amaId);
}

class ApiAmas implements AmasRepository {
  ApiAmas(this.api);

  final ApiClient api;

  static const maxQuestions = 3;
  static const minMinutes = 15;
  static const maxMinutes = 120;

  @override
  Future<List<Ama>> list() async => [
    for (final a in (await api.get('/amas') as List).cast<Map<String, dynamic>>())
      Ama.fromJson(a),
  ];

  @override
  Future<AmaDetail> detail(String amaId) async => AmaDetail.fromJson(
    await api.get('/amas/$amaId') as Map<String, dynamic>,
  );

  @override
  Future<void> ask(
    String amaId,
    String question, {
    bool anonymous = false,
    bool sendAnyway = false,
  }) async {
    try {
      await api.post(
        '/amas/$amaId/questions',
        body: {
          'question': question.trim(),
          'anonymous': anonymous,
          'sendAnyway': sendAnyway,
        },
      );
    } on ApiError catch (e) {
      if (e.code == 'EMPATHY_CHECK') throw EmpathyCheck(e.detail);
      rethrow;
    }
  }

  @override
  Future<void> vote(String amaId, String questionId, {required bool on}) => on
      ? api.post('/amas/$amaId/questions/$questionId/vote')
      : api.delete('/amas/$amaId/questions/$questionId/vote');

  @override
  Future<Ama> schedule({
    required String title,
    required DateTime startsAt,
    int minutes = 60,
    String? corridorRegion,
  }) async {
    final region = corridorRegion?.trim().toUpperCase() ?? '';
    return Ama.fromJson(
      await api.post(
            '/amas',
            body: {
              'title': title.trim(),
              'startsAt': startsAt.toUtc().toIso8601String(),
              'minutes': minutes,
              if (region.isNotEmpty) 'corridorRegion': region,
            },
          )
          as Map<String, dynamic>,
    );
  }

  @override
  Future<void> answer(String amaId, String questionId, String answer) =>
      api.post(
        '/amas/$amaId/questions/$questionId/answer',
        body: {'answer': answer.trim()},
      );

  @override
  Future<void> hide(String amaId, String questionId) =>
      api.post('/amas/$amaId/questions/$questionId/hide');

  @override
  Future<void> cancel(String amaId) => api.delete('/amas/$amaId');
}

class FakeAmas implements AmasRepository {
  FakeAmas({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final now = _clock();
    _amas.add(
      Ama(
        id: 'ama1',
        title: 'Growing up in Kochi, cooking in Mumbai',
        hostName: 'Ranveer',
        hostHandle: 'chef.ranveer',
        startsAt: now.subtract(const Duration(minutes: 10)),
        endsAt: now.add(const Duration(minutes: 50)),
        state: 'LIVE',
        corridorRegion: 'IN-KL',
        canAsk: true,
      ),
    );
    _questions['ama1'] = [
      const AmaQuestion(
        id: 'q1',
        question: 'What do you miss most from home?',
        askedBy: 'Someone from IN-KL',
        answer: 'Kappa and fish curry at my grandmother\'s.',
      ),
    ];
  }

  final DateTime Function() _clock;
  final _amas = <Ama>[];
  final _questions = <String, List<AmaQuestion>>{};
  final votes = <String>{};

  @override
  Future<List<Ama>> list() async => List.of(_amas);

  @override
  Future<AmaDetail> detail(String amaId) async => AmaDetail(
    ama: _amas.firstWhere((a) => a.id == amaId),
    questions: [
      for (final q in _questions[amaId] ?? const <AmaQuestion>[])
        AmaQuestion(
          id: q.id,
          question: q.question,
          askedBy: q.askedBy,
          answer: q.answer,
          mine: q.mine,
          youVoted: votes.contains(q.id),
        ),
    ],
  );

  @override
  Future<void> ask(
    String amaId,
    String question, {
    bool anonymous = false,
    bool sendAnyway = false,
  }) async {
    final list = _questions.putIfAbsent(amaId, () => []);
    list.add(
      AmaQuestion(
        id: '$amaId-q${list.length + 1}',
        question: question.trim(),
        askedBy: anonymous ? 'Someone from IN-KL' : 'You',
        mine: true,
      ),
    );
  }

  @override
  Future<void> vote(String amaId, String questionId, {required bool on}) async =>
      on ? votes.add(questionId) : votes.remove(questionId);

  @override
  Future<Ama> schedule({
    required String title,
    required DateTime startsAt,
    int minutes = 60,
    String? corridorRegion,
  }) async {
    final ama = Ama(
      id: 'ama${_amas.length + 1}',
      title: title.trim(),
      hostName: 'You',
      startsAt: startsAt,
      endsAt: startsAt.add(Duration(minutes: minutes)),
      state: 'UPCOMING',
      corridorRegion: (corridorRegion ?? '').trim().isEmpty
          ? null
          : corridorRegion!.trim().toUpperCase(),
      youHost: true,
    );
    _amas.add(ama);
    return ama;
  }

  @override
  Future<void> answer(String amaId, String questionId, String answer) async {}

  @override
  Future<void> hide(String amaId, String questionId) async =>
      _questions[amaId]?.removeWhere((q) => q.id == questionId);

  @override
  Future<void> cancel(String amaId) async =>
      _amas.removeWhere((a) => a.id == amaId);
}
