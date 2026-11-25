import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// Someone in a thread, by first name and a per-thread handle (never a user id).
class ThreadMember {
  const ThreadMember({
    required this.handle,
    required this.firstName,
    this.startedIt = false,
    this.you = false,
  });

  final String handle;
  final String firstName;
  final bool startedIt;
  final bool you;

  factory ThreadMember.fromJson(Map<String, dynamic> j) => ThreadMember(
    handle: j['handle'] as String,
    firstName: j['firstName'] as String? ?? '',
    startedIt: j['startedIt'] as bool? ?? false,
    you: j['you'] as bool? ?? false,
  );
}

/// A Collaborative Thread: one shared story among up to 12 friends, open 1 to 7 days, then read-only.
class StoryThread {
  const StoryThread({
    required this.id,
    required this.title,
    required this.invited,
    required this.open,
    required this.endsAt,
    this.youStartedIt = false,
    this.members = const [],
  });

  final String id;
  final String title;

  /// Invited and not yet answered (otherwise you're in).
  final bool invited;

  /// Still taking posts.
  final bool open;
  final DateTime endsAt;
  final bool youStartedIt;
  final List<ThreadMember> members;

  /// From ThreadView.
  factory StoryThread.fromJson(Map<String, dynamic> j) => StoryThread(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    invited: j['myStatus'] == 'INVITED',
    open: j['open'] as bool? ?? false,
    endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
    youStartedIt: j['youStartedIt'] as bool? ?? false,
    members: [
      for (final m in (j['members'] as List? ?? const []))
        ThreadMember.fromJson((m as Map).cast<String, dynamic>()),
    ],
  );
}

class ThreadPost {
  const ThreadPost({
    required this.id,
    required this.firstName,
    required this.mine,
    required this.postedAt,
    this.caption,
    this.mediaUrl,
    this.concern,
  });

  final String id;
  final String firstName;
  final bool mine;
  final DateTime postedAt;
  final String? caption;
  final String? mediaUrl;

  /// The Empathy Mirror's "Does this bother you?" for readers.
  final String? concern;

  /// From PostView.
  factory ThreadPost.fromJson(Map<String, dynamic> j) => ThreadPost(
    id: j['id'] as String,
    firstName: j['firstName'] as String? ?? '',
    mine: j['mine'] as bool? ?? false,
    postedAt: DateTime.parse(j['postedAt'] as String).toLocal(),
    caption: j['caption'] as String?,
    mediaUrl: j['mediaUrl'] as String?,
    concern: (j['concern'] as Map?)?['question'] as String?,
  );
}

abstract interface class ThreadsRepository {
  Future<List<StoryThread>> list();

  Future<StoryThread> thread(String threadId);

  /// [days] is 1 to 7; invitees come from your own Connections.
  Future<StoryThread> create(
    String title, {
    int days = 3,
    List<String> inviteConnectionIds = const [],
  });

  Future<StoryThread> invite(String threadId, List<String> connectionIds);

  Future<StoryThread> accept(String threadId);

  Future<void> decline(String threadId);

  Future<void> leave(String threadId);

  /// Oldest first.
  Future<List<ThreadPost>> posts(String threadId);

  /// A words-only post. Throws [EmpathyCheck] when the Empathy Mirror asks for a second look.
  Future<ThreadPost> post(String threadId, String caption, {bool sendAnyway = false});

  Future<void> deletePost(String threadId, String postId);
}

class ApiThreads implements ThreadsRepository {
  ApiThreads(this.api);

  final ApiClient api;

  static const maxTitle = 60;
  static const maxCaption = 200;
  static const maxMembers = 12;

  StoryThread _thread(dynamic json) =>
      StoryThread.fromJson(json as Map<String, dynamic>);

  @override
  Future<List<StoryThread>> list() async => [
    for (final t in (await api.get('/threads') as List).cast<Map<String, dynamic>>())
      StoryThread.fromJson(t),
  ];

  @override
  Future<StoryThread> thread(String threadId) async =>
      _thread(await api.get('/threads/$threadId'));

  @override
  Future<StoryThread> create(
    String title, {
    int days = 3,
    List<String> inviteConnectionIds = const [],
  }) async => _thread(
    await api.post(
      '/threads',
      body: {
        'title': title.trim(),
        'days': days,
        'inviteConnectionIds': inviteConnectionIds,
      },
    ),
  );

  @override
  Future<StoryThread> invite(String threadId, List<String> connectionIds) async =>
      _thread(
        await api.post(
          '/threads/$threadId/invite',
          body: {'connectionIds': connectionIds},
        ),
      );

  @override
  Future<StoryThread> accept(String threadId) async =>
      _thread(await api.post('/threads/$threadId/accept'));

  @override
  Future<void> decline(String threadId) =>
      api.post('/threads/$threadId/decline');

  @override
  Future<void> leave(String threadId) => api.post('/threads/$threadId/leave');

  @override
  Future<List<ThreadPost>> posts(String threadId) async {
    final list = (await api.get(
      '/threads/$threadId/posts',
      query: {'limit': 50},
    ) as List).cast<Map<String, dynamic>>();
    // The server pages newest first; the thread reads oldest first.
    return [for (final p in list.reversed) ThreadPost.fromJson(p)];
  }

  @override
  Future<ThreadPost> post(
    String threadId,
    String caption, {
    bool sendAnyway = false,
  }) async {
    try {
      final json = await api.post(
        '/threads/$threadId/posts',
        body: {
          'kind': 'TEXT',
          'caption': caption.trim(),
          'sendAnyway': sendAnyway,
        },
      );
      return ThreadPost.fromJson(json as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.code == 'EMPATHY_CHECK') throw EmpathyCheck(e.detail);
      rethrow;
    }
  }

  @override
  Future<void> deletePost(String threadId, String postId) =>
      api.delete('/threads/$threadId/posts/$postId');
}

class FakeThreads implements ThreadsRepository {
  FakeThreads({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _threads.add(
      StoryThread(
        id: 't1',
        title: 'Goa trip 🌴',
        invited: true,
        open: true,
        endsAt: _clock().add(const Duration(days: 4)),
        members: const [
          ThreadMember(handle: 'a', firstName: 'Rohan', startedIt: true),
          ThreadMember(handle: 'b', firstName: 'Zoya'),
        ],
      ),
    );
    _posts['t1'] = [
      ThreadPost(
        id: 'p1',
        firstName: 'Rohan',
        mine: false,
        postedAt: _clock().subtract(const Duration(hours: 2)),
        caption: 'Landed! Beach by 4?',
      ),
    ];
  }

  final DateTime Function() _clock;
  final _threads = <StoryThread>[];
  final _posts = <String, List<ThreadPost>>{};

  StoryThread _replace(StoryThread t, {bool? invited}) {
    final next = StoryThread(
      id: t.id,
      title: t.title,
      invited: invited ?? t.invited,
      open: t.open,
      endsAt: t.endsAt,
      youStartedIt: t.youStartedIt,
      members: [
        ...t.members,
        if (invited == false) const ThreadMember(handle: 'me', firstName: 'You', you: true),
      ],
    );
    _threads[_threads.indexWhere((x) => x.id == t.id)] = next;
    return next;
  }

  @override
  Future<List<StoryThread>> list() async => List.of(_threads);

  @override
  Future<StoryThread> thread(String threadId) async =>
      _threads.firstWhere((t) => t.id == threadId);

  @override
  Future<StoryThread> create(
    String title, {
    int days = 3,
    List<String> inviteConnectionIds = const [],
  }) async {
    final thread = StoryThread(
      id: 't${_threads.length + 1}',
      title: title.trim(),
      invited: false,
      open: true,
      endsAt: _clock().add(Duration(days: days)),
      youStartedIt: true,
      members: const [
        ThreadMember(handle: 'me', firstName: 'You', startedIt: true, you: true),
      ],
    );
    _threads.insert(0, thread);
    return thread;
  }

  @override
  Future<StoryThread> invite(String threadId, List<String> connectionIds) =>
      thread(threadId);

  @override
  Future<StoryThread> accept(String threadId) async =>
      _replace(await thread(threadId), invited: false);

  @override
  Future<void> decline(String threadId) async =>
      _threads.removeWhere((t) => t.id == threadId);

  @override
  Future<void> leave(String threadId) async =>
      _threads.removeWhere((t) => t.id == threadId);

  @override
  Future<List<ThreadPost>> posts(String threadId) async =>
      List.of(_posts[threadId] ?? const []);

  @override
  Future<ThreadPost> post(
    String threadId,
    String caption, {
    bool sendAnyway = false,
  }) async {
    final list = _posts.putIfAbsent(threadId, () => []);
    final post = ThreadPost(
      id: '$threadId-${list.length}',
      firstName: 'You',
      mine: true,
      postedAt: _clock(),
      caption: caption.trim(),
    );
    list.add(post);
    return post;
  }

  @override
  Future<void> deletePost(String threadId, String postId) async =>
      _posts[threadId]?.removeWhere((p) => p.id == postId);
}
